-- =============================================================================
-- family_invitations.test.sql
-- Plain SQL tests with full isolation and strict assertions (Testing Rollbacks)
-- =============================================================================

DO $$
DECLARE
  v_owner_id UUID := gen_random_uuid();
  v_member_id UUID := gen_random_uuid();
  v_viewer_id UUID := gen_random_uuid();
  v_revoke_id UUID := gen_random_uuid();
  
  v_family_id UUID;
  v_owner_member_id UUID;
  v_member_member_id UUID;
  v_viewer_member_id UUID;
  
  v_inv_id UUID;
  v_inv_id_2 UUID;
  
  v_cat_id UUID;
  v_wal_id UUID;
  
  v_status public.member_status;
  v_inv_status public.family_invitation_status;
BEGIN
  -- 1. Setup Isolated Environment
  INSERT INTO auth.users (id, email, aud, role, encrypted_password, created_at, updated_at) 
  VALUES (v_owner_id, 'owner@mezan.com', 'authenticated', 'authenticated', 'crypt', now(), now());
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_owner_id, 'email', 'owner@mezan.com')::text, true);
  PERFORM set_config('role', 'authenticated', true);

  -- Create family (OWNER)
  SELECT family_id, member_id INTO v_family_id, v_owner_member_id 
  FROM public.fn_create_initial_family('Test Family', 'Owner User');

  -- Create a secondary member
  INSERT INTO auth.users (id, email, aud, role, encrypted_password, created_at, updated_at) 
  VALUES (v_member_id, 'member@mezan.com', 'authenticated', 'authenticated', 'crypt', now(), now());
  INSERT INTO public.family_members (family_id, user_id, role, status, display_name)
  VALUES (v_family_id, v_member_id, 'MEMBER', 'ACTIVE', 'Member User')
  RETURNING id INTO v_member_member_id;

  -- Create a viewer
  INSERT INTO auth.users (id, email, aud, role, encrypted_password, created_at, updated_at) 
  VALUES (v_viewer_id, 'viewer@mezan.com', 'authenticated', 'authenticated', 'crypt', now(), now());
  INSERT INTO public.family_members (family_id, user_id, role, status, display_name)
  VALUES (v_family_id, v_viewer_id, 'VIEWER', 'ACTIVE', 'Viewer User')
  RETURNING id INTO v_viewer_member_id;

  -- Get system categories & wallet
  SELECT id INTO v_cat_id FROM public.categories WHERE direction = 'INCOME' AND family_id IS NULL LIMIT 1;
  SELECT id INTO v_wal_id FROM public.wallets WHERE family_id = v_family_id LIMIT 1;

  -- 2. Test: Non-owner cannot invite
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_member_id, 'email', 'member@mezan.com')::text, true);
  BEGIN
    PERFORM public.fn_create_family_invitation(v_family_id, 'test1@mezan.com', 'MEMBER', 'Test', now() + interval '1 day');
    RAISE EXCEPTION 'TEST_FAILED: Non-owner was able to invite';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%PERMISSION_DENIED%' THEN RAISE; END IF;
  END;

  -- 3. Test: Owner can invite
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_owner_id, 'email', 'owner@mezan.com')::text, true);
  v_inv_id := public.fn_create_family_invitation(v_family_id, 'invite1@mezan.com', 'MEMBER', 'Invite 1', now() + interval '1 day');
  
  IF NOT EXISTS (SELECT 1 FROM public.audit_events WHERE action = 'MEMBER_INVITED' AND target_id = v_inv_id) THEN
    RAISE EXCEPTION 'TEST_FAILED: Audit event for invitation not found';
  END IF;

  -- Test: Cannot invite new OWNER in MVP
  BEGIN
    PERFORM public.fn_create_family_invitation(v_family_id, 'invite2@mezan.com', 'OWNER', 'Invite 2', now() + interval '1 day');
    RAISE EXCEPTION 'TEST_FAILED: Owner could invite another owner';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_ROLE%' THEN RAISE; END IF;
  END;

  -- 4. Test: Duplicate pending invitations
  BEGIN
    PERFORM public.fn_create_family_invitation(v_family_id, 'invite1@mezan.com', 'VIEWER', 'Invite 1 Dup', now() + interval '1 day');
    RAISE EXCEPTION 'TEST_FAILED: Duplicate pending invitations allowed';
  EXCEPTION WHEN unique_violation THEN
    -- Expected
  END;

  -- 5. Test: Accept Invitation (Email Mismatch and Success)
  INSERT INTO auth.users (id, email, aud, role, encrypted_password, created_at, updated_at) 
  VALUES (gen_random_uuid(), 'invite1@mezan.com', 'authenticated', 'authenticated', 'crypt', now(), now());
  
  -- Try to accept with different email
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_member_id, 'email', 'member@mezan.com')::text, true);
  BEGIN
    PERFORM public.fn_accept_family_invitation(v_inv_id);
    RAISE EXCEPTION 'TEST_FAILED: Accepted invitation with mismatched email';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%EMAIL_MISMATCH%' THEN RAISE; END IF;
  END;

  -- Accept successfully
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', (SELECT id FROM auth.users WHERE email = 'invite1@mezan.com'), 'email', 'invite1@mezan.com')::text, true);
  PERFORM public.fn_accept_family_invitation(v_inv_id);

  SELECT status INTO v_status FROM public.family_members WHERE user_id = (SELECT id FROM auth.users WHERE email = 'invite1@mezan.com');
  IF v_status != 'ACTIVE' THEN
    RAISE EXCEPTION 'TEST_FAILED: Member not ACTIVE after acceptance';
  END IF;

  -- Try to accept again
  BEGIN
    PERFORM public.fn_accept_family_invitation(v_inv_id);
    RAISE EXCEPTION 'TEST_FAILED: Accepted an already accepted invitation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_STATUS%' THEN RAISE; END IF;
  END;

  -- 6. Test: Role Changes
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_member_id, 'email', 'member@mezan.com')::text, true);
  BEGIN
    PERFORM public.fn_change_family_member_role(v_family_id, v_member_member_id, 'OWNER');
    RAISE EXCEPTION 'TEST_FAILED: Member could change roles';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%PERMISSION_DENIED%' THEN RAISE; END IF;
  END;

  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_owner_id, 'email', 'owner@mezan.com')::text, true);
  PERFORM public.fn_change_family_member_role(v_family_id, v_member_member_id, 'VIEWER');
  
  IF NOT EXISTS (SELECT 1 FROM public.audit_events WHERE action = 'MEMBER_ROLE_CHANGED' AND target_id = v_member_member_id) THEN
    RAISE EXCEPTION 'TEST_FAILED: Audit event for role change not found';
  END IF;

  -- 7. Test: Last OWNER protection
  BEGIN
    PERFORM public.fn_change_family_member_role(v_family_id, v_owner_member_id, 'MEMBER');
    RAISE EXCEPTION 'TEST_FAILED: Demoted last active owner';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%LAST_OWNER_PROTECTION%' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.fn_suspend_family_member(v_family_id, v_owner_member_id);
    RAISE EXCEPTION 'TEST_FAILED: Suspended self (protects last owner)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_ACTION%' THEN RAISE; END IF;
  END;

  -- 8. Test: Suspend/Reactivate
  PERFORM public.fn_suspend_family_member(v_family_id, v_member_member_id);
  
  SELECT status INTO v_status FROM public.family_members WHERE id = v_member_member_id;
  IF v_status != 'SUSPENDED' THEN
    RAISE EXCEPTION 'TEST_FAILED: Member not suspended';
  END IF;

  PERFORM public.fn_reactivate_family_member(v_family_id, v_member_member_id);
  SELECT status INTO v_status FROM public.family_members WHERE id = v_member_member_id;
  IF v_status != 'ACTIVE' THEN
    RAISE EXCEPTION 'TEST_FAILED: Member not reactivated';
  END IF;

  -- 9. Test: VIEWER cannot call mutating financial RPCs
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_viewer_id, 'email', 'viewer@mezan.com')::text, true);
  BEGIN
    -- Corrected signature for fn_record_income: p_family_id, p_amount, p_to_wallet_id, p_category_id, p_description, p_effective_at, p_notes
    PERFORM public.fn_record_income(v_family_id, 1000.00, v_wal_id, v_cat_id, 'Test', now(), null);
    RAISE EXCEPTION 'TEST_FAILED: VIEWER could record income';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%PERMISSION_DENIED%' THEN RAISE; END IF;
  END;

  -- 10. Test: Revoke Invitation
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_owner_id, 'email', 'owner@mezan.com')::text, true);
  v_inv_id_2 := public.fn_create_family_invitation(v_family_id, 'revoke@mezan.com', 'MEMBER', 'Revoke Test', now() + interval '1 day');

  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_member_id, 'email', 'member@mezan.com')::text, true);
  BEGIN
    PERFORM public.fn_revoke_family_invitation(v_family_id, v_inv_id_2);
    RAISE EXCEPTION 'TEST_FAILED: Member could revoke invitation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%PERMISSION_DENIED%' THEN RAISE; END IF;
  END;

  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_owner_id, 'email', 'owner@mezan.com')::text, true);
  PERFORM public.fn_revoke_family_invitation(v_family_id, v_inv_id_2);

  SELECT status INTO v_inv_status FROM public.family_invitations WHERE id = v_inv_id_2;
  IF v_inv_status != 'REVOKED' THEN
    RAISE EXCEPTION 'TEST_FAILED: Invitation not revoked';
  END IF;

  -- Try to accept revoked
  INSERT INTO auth.users (id, email, aud, role, encrypted_password, created_at, updated_at) 
  VALUES (v_revoke_id, 'revoke@mezan.com', 'authenticated', 'authenticated', 'crypt', now(), now());
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_revoke_id, 'email', 'revoke@mezan.com')::text, true);
  BEGIN
    PERFORM public.fn_accept_family_invitation(v_inv_id_2);
    RAISE EXCEPTION 'TEST_FAILED: Accepted revoked invitation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_STATUS%' THEN RAISE; END IF;
  END;

  -- 11. Test: Direct Member Creation
  DECLARE
    v_direct_user_id UUID := gen_random_uuid();
    v_direct_member_id UUID;
  BEGIN
    INSERT INTO auth.users (id, email, aud, role, encrypted_password, created_at, updated_at) 
    VALUES (v_direct_user_id, 'direct@mezan.com', 'authenticated', 'authenticated', 'crypt', now(), now());

    -- Non-owner cannot create directly
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_member_id, 'email', 'member@mezan.com')::text, true);
    BEGIN
      PERFORM public.fn_add_existing_user_to_family(v_family_id, v_direct_user_id, 'MEMBER', 'Direct User');
      RAISE EXCEPTION 'TEST_FAILED: Non-owner created member directly';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%PERMISSION_DENIED%' THEN RAISE; END IF;
    END;

    -- Owner cannot create new OWNER directly
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_owner_id, 'email', 'owner@mezan.com')::text, true);
    BEGIN
      PERFORM public.fn_add_existing_user_to_family(v_family_id, v_direct_user_id, 'OWNER', 'Direct User');
      RAISE EXCEPTION 'TEST_FAILED: Owner created new owner directly';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%INVALID_ROLE%' THEN RAISE; END IF;
    END;

    -- Owner can create MEMBER directly
    v_direct_member_id := public.fn_add_existing_user_to_family(v_family_id, v_direct_user_id, 'MEMBER', 'Direct User');

    IF NOT EXISTS (SELECT 1 FROM public.audit_events WHERE action = 'SETTINGS_CHANGED' AND target_id = v_direct_member_id) THEN
      RAISE EXCEPTION 'TEST_FAILED: Audit event for direct creation not found';
    END IF;

    -- Cannot add same user to another family (ONE_FAMILY_LIMIT)
    DECLARE
      v_second_owner_user_id UUID := gen_random_uuid();
      v_second_family_id UUID;
      v_second_owner_id UUID;
    BEGIN
      -- Create a new owner user
      INSERT INTO auth.users (id, email, aud, role, encrypted_password, created_at, updated_at) 
      VALUES (v_second_owner_user_id, 'owner2@mezan.com', 'authenticated', 'authenticated', 'crypt', now(), now());
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_second_owner_user_id, 'email', 'owner2@mezan.com')::text, true);

      SELECT family_id, member_id INTO v_second_family_id, v_second_owner_id 
      FROM public.fn_create_initial_family('Second Family', 'Owner User 2');
      
      BEGIN
        PERFORM public.fn_add_existing_user_to_family(v_second_family_id, v_direct_user_id, 'MEMBER', 'Direct User 2');
        RAISE EXCEPTION 'TEST_FAILED: User added to second family';
      EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%ONE_FAMILY_LIMIT%' THEN RAISE; END IF;
      END;
    END;
  END;

  -- Cleanup auth mock
  PERFORM set_config('role', 'postgres', true);

  RAISE EXCEPTION 'TEST_SUCCESS_ROLLBACK';
EXCEPTION
  WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    
    IF SQLERRM = 'TEST_SUCCESS_ROLLBACK' THEN
      RAISE NOTICE 'All tests passed! (Errors caught and rollbacks verified)';
    ELSE
      RAISE;
    END IF;
END $$;
