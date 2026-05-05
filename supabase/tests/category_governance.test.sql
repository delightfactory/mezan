BEGIN;

-- Setup test isolated environment
DO $$
DECLARE
  v_owner_user_id UUID := gen_random_uuid();
  v_member_user_id UUID := gen_random_uuid();
  v_other_owner_user_id UUID := gen_random_uuid();
  v_family_id UUID;
  v_other_family_id UUID;
  v_owner_member_id UUID;
  v_member_member_id UUID;
  
  v_system_category_id UUID;
  v_family_category_id UUID;
BEGIN
  -- 1. Setup Auth Mock
  INSERT INTO auth.users (id, email, aud, role, encrypted_password, created_at, updated_at) 
  VALUES 
  (v_owner_user_id, 'owner@categorytest.com', 'authenticated', 'authenticated', 'crypt', now(), now()),
  (v_member_user_id, 'member@categorytest.com', 'authenticated', 'authenticated', 'crypt', now(), now()),
  (v_other_owner_user_id, 'other@categorytest.com', 'authenticated', 'authenticated', 'crypt', now(), now());

  -- Act as OWNER
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_owner_user_id, 'email', 'owner@categorytest.com')::text, true);
  PERFORM set_config('role', 'authenticated', true);

  -- Create a family
  SELECT family_id, member_id INTO v_family_id, v_owner_member_id 
  FROM public.fn_create_initial_family('Category Test Family', 'Owner');

  -- Create another family for testing parent from another family
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_other_owner_user_id, 'email', 'other@categorytest.com')::text, true);
  SELECT family_id INTO v_other_family_id FROM public.fn_create_initial_family('Other Family', 'Other Owner');
  
  -- Switch back to OWNER
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_owner_user_id, 'email', 'owner@categorytest.com')::text, true);

  -- Add a MEMBER
  INSERT INTO public.family_members (family_id, user_id, role, status, display_name)
  VALUES (v_family_id, v_member_user_id, 'MEMBER', 'ACTIVE', 'Member')
  RETURNING id INTO v_member_member_id;

  -- Get a system category (family_id IS NULL)
  SELECT id INTO v_system_category_id FROM public.categories WHERE family_id IS NULL AND direction = 'EXPENSE' LIMIT 1;

  -- 2. Test: OWNER can create a category
  v_family_category_id := public.fn_create_family_category(
    v_family_id,
    'Family Expense Cat',
    'Fam Exp',
    'EXPENSE',
    'VARIABLE_BUDGETED',
    v_system_category_id,
    50,
    null
  );

  IF NOT EXISTS (SELECT 1 FROM public.audit_events WHERE action = 'SETTINGS_CHANGED' AND target_id = v_family_category_id AND actor_id = v_owner_member_id) THEN
    RAISE EXCEPTION 'TEST_FAILED: Audit event for category creation not found with correct actor_id';
  END IF;

  -- 3. Test: Prevent SYSTEM behavior for family categories
  BEGIN
    PERFORM public.fn_create_family_category(v_family_id, 'System Fake', null, 'EXPENSE', 'SYSTEM', null, 50, null);
    RAISE EXCEPTION 'TEST_FAILED: Created family category with SYSTEM behavior';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_ACTION%' THEN RAISE; END IF;
  END;

  -- 4. Test: Prevent parent from another family
  DECLARE
    v_other_cat_id UUID;
  BEGIN
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_other_owner_user_id, 'email', 'other@categorytest.com')::text, true);
    v_other_cat_id := public.fn_create_family_category(v_other_family_id, 'Other Exp', null, 'EXPENSE', 'VARIABLE_BUDGETED', null, 50, null);
    
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_owner_user_id, 'email', 'owner@categorytest.com')::text, true);
    PERFORM public.fn_create_family_category(v_family_id, 'My Exp', null, 'EXPENSE', 'VARIABLE_BUDGETED', v_other_cat_id, 50, null);
    RAISE EXCEPTION 'TEST_FAILED: Used parent from another family';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_PARENT%' THEN RAISE; END IF;
  END;

  -- 5. Test: Cannot use parent from different direction
  BEGIN
    PERFORM public.fn_create_family_category(v_family_id, 'Mismatch', 'Miss', 'INCOME', 'VARIABLE_BUDGETED', v_system_category_id, 50, null);
    RAISE EXCEPTION 'TEST_FAILED: Created category with parent of different direction';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_DIRECTION%' THEN RAISE; END IF;
  END;

  -- 6. Test: MEMBER cannot create a category
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_member_user_id, 'email', 'member@categorytest.com')::text, true);
  BEGIN
    PERFORM public.fn_create_family_category(v_family_id, 'Member Cat', null, 'EXPENSE', 'VARIABLE_BUDGETED', null, 50, null);
    RAISE EXCEPTION 'TEST_FAILED: MEMBER created a category';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%PERMISSION_DENIED%' THEN RAISE; END IF;
  END;

  -- 7. Test: OWNER can update a family category
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_owner_user_id, 'email', 'owner@categorytest.com')::text, true);
  PERFORM public.fn_update_family_category(v_family_id, v_family_category_id, 'Updated Fam Cat', null, 'FIXED_ESSENTIAL', null, 20, null);
  
  IF NOT EXISTS (SELECT 1 FROM public.categories WHERE id = v_family_category_id AND name_ar = 'Updated Fam Cat' AND priority_level = 20) THEN
    RAISE EXCEPTION 'TEST_FAILED: Family category not updated correctly';
  END IF;

  -- 8. Test: Cannot update a system category
  BEGIN
    PERFORM public.fn_update_family_category(v_family_id, v_system_category_id, 'Hacked System', null, 'FIXED_ESSENTIAL', null, 10, null);
    RAISE EXCEPTION 'TEST_FAILED: System category was updated';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_ACTION%' THEN RAISE; END IF;
  END;

  -- 9. Test: Prevent archiving if used in active budget
  DECLARE
    v_budget_cat_id UUID;
  BEGIN
    v_budget_cat_id := public.fn_create_family_category(v_family_id, 'Budget Cat', null, 'EXPENSE', 'VARIABLE_BUDGETED', null, 50, null);
    
    INSERT INTO public.budgets (family_id, category_id, allocated_amount, cycle_start, cycle_end, period)
    VALUES (v_family_id, v_budget_cat_id, 1000, CURRENT_DATE - INTERVAL '1 day', CURRENT_DATE + INTERVAL '30 days', 'MONTHLY');

    BEGIN
      PERFORM public.fn_archive_family_category(v_family_id, v_budget_cat_id);
      RAISE EXCEPTION 'TEST_FAILED: Archived category used in active budget';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%HAS_ACTIVE_BUDGET%' THEN RAISE; END IF;
    END;
  END;

  -- 10. Test: Archive with children block
  DECLARE
    v_child_id UUID;
  BEGIN
    v_child_id := public.fn_create_family_category(v_family_id, 'Child Cat', null, 'EXPENSE', 'VARIABLE_BUDGETED', v_family_category_id, 50, null);
    
    BEGIN
      PERFORM public.fn_archive_family_category(v_family_id, v_family_category_id);
      RAISE EXCEPTION 'TEST_FAILED: Archived parent with active child';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%HAS_ACTIVE_CHILDREN%' THEN RAISE; END IF;
    END;

    -- Archive child first
    PERFORM public.fn_archive_family_category(v_family_id, v_child_id);
  END;

  -- 11. Test: Archive successful if no active children/budgets/commitments
  PERFORM public.fn_archive_family_category(v_family_id, v_family_category_id);
  IF NOT EXISTS (SELECT 1 FROM public.categories WHERE id = v_family_category_id AND is_archived = true) THEN
    RAISE EXCEPTION 'TEST_FAILED: Category not archived';
  END IF;

  -- 12. Test: Cannot archive system category
  BEGIN
    PERFORM public.fn_archive_family_category(v_family_id, v_system_category_id);
    RAISE EXCEPTION 'TEST_FAILED: System category was archived';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_ACTION%' THEN RAISE; END IF;
  END;

  -- Cleanup auth mock
  PERFORM set_config('role', 'postgres', true);
  RAISE EXCEPTION 'TEST_SUCCESS_ROLLBACK';
EXCEPTION
  WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    IF SQLERRM = 'TEST_SUCCESS_ROLLBACK' THEN
      RAISE NOTICE 'Category Governance Tests Passed!';
    ELSE
      RAISE;
    END IF;
END $$;

ROLLBACK;
