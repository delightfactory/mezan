-- =============================================================================
-- Mezan: 00040_phase4a_tests.sql
-- Test cases for Phase 4A Hardening
-- =============================================================================

DO $$
DECLARE
  v_family_id UUID;
  v_owner_id UUID;
  v_suspended_id UUID;
  v_alloc_w UUID;
  v_real_w UUID;
  v_cat_id UUID;
  v_com_id UUID;
  v_occ_id UUID;
  v_debt_id UUID;
  v_gameya_id UUID;
  v_overload_count INT;
  v_user_id UUID := gen_random_uuid();
  v_suspended_user_id UUID := gen_random_uuid();
  v_safe_spend NUMERIC;
BEGIN
  -- 1. Verify no old overload for fn_pay_commitment_occurrence
  SELECT count(*) INTO v_overload_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' 
    AND p.proname = 'fn_pay_commitment_occurrence';
  
  -- We expect exactly 1 definition now (the new one with p_amount NUMERIC)
  IF v_overload_count > 1 THEN
    RAISE EXCEPTION 'TEST FAILED: Found % overloads for fn_pay_commitment_occurrence. Expected 1.', v_overload_count;
  END IF;

  -- Must be postgres to insert into auth.users
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth.users (id, email) VALUES (v_user_id, 'testowner@test.com');
  
  -- Now set auth context
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user_id)::text, true);

  -- Setup Family and Wallets
  SELECT family_id, member_id INTO v_family_id, v_owner_id FROM public.fn_create_initial_family('Test Family', 'Test Owner');
  
  -- Create category
  v_cat_id := public.fn_create_family_category(
    p_family_id := v_family_id, 
    p_name_ar := 'Test Cat', 
    p_direction := 'INCOME',
    p_priority_level := 1
  );
  
  -- Setup real wallet
  INSERT INTO public.wallets (family_id, name, type, created_by, balance) 
  VALUES (v_family_id, 'Test Real', 'REAL', v_owner_id, 10000) RETURNING id INTO v_real_w;
  
  -- Setup alloc wallet
  INSERT INTO public.wallets (family_id, name, type, created_by, balance) 
  VALUES (v_family_id, 'Test Alloc', 'ALLOCATED', v_owner_id, 0) RETURNING id INTO v_alloc_w;

  -- Create a suspended member
  -- Must be postgres to insert into auth.users
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth.users (id, email) VALUES (v_suspended_user_id, 'suspended@test.com');
  PERFORM set_config('role', 'authenticated', true);
  
  INSERT INTO public.family_members (family_id, user_id, role, status)
  VALUES (v_family_id, v_suspended_user_id, 'MEMBER', 'SUSPENDED')
  RETURNING id INTO v_suspended_id;

  -- 2. Test Safe to spend calculation components
  -- A. Commitment (Partial Payment)
  INSERT INTO public.commitments (
    family_id, name, amount, frequency, start_date, wallet_id, category_id, priority_level
  ) VALUES (
    v_family_id, 'Test Com', 1000, 'MONTHLY', CURRENT_DATE, v_real_w, v_cat_id, 1
  ) RETURNING id INTO v_com_id;

  INSERT INTO public.commitment_occurrences (
    commitment_id, family_id, amount, due_date, status
  ) VALUES (
    v_com_id, v_family_id, 1000, CURRENT_DATE, 'UPCOMING'
  ) RETURNING id INTO v_occ_id;
  
  -- Partial pay 400
  PERFORM public.fn_pay_commitment_occurrence(v_family_id, v_occ_id, v_real_w, 400, now(), 'Test partial');
  
  -- Check occurrence status
  IF (SELECT status FROM public.commitment_occurrences WHERE id = v_occ_id) != 'PARTIALLY_PAID' THEN
    RAISE EXCEPTION 'TEST FAILED: Occurrence not marked as PARTIALLY_PAID';
  END IF;

  -- B. Active Debt (Borrowed From)
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.debts (family_id, entity_name, direction, original_amount, remaining_amount, created_by, status, due_date, next_due_date, payment_schedule_type)
  VALUES (v_family_id, 'Test Lender', 'BORROWED_FROM', 2000, 2000, v_owner_id, 'ACTIVE', CURRENT_DATE, CURRENT_DATE, 'ONE_TIME');
  PERFORM set_config('role', 'authenticated', true);

  -- C. Gameya (Flexible)
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.gameya_circles (
    family_id, name, monthly_installment, payment_frequency, turn_frequency, total_months, start_date, is_flexible, status, payout_month, payout_turn
  ) VALUES (
    v_family_id, 'Test Gameya', 500, 'MONTHLY', 'MONTHLY', 10, CURRENT_DATE, true, 'SAVING_PHASE', 5, 5
  ) RETURNING id INTO v_gameya_id;

  INSERT INTO public.gameya_installments (
    gameya_id, family_id, amount, due_date, status, installment_number
  ) VALUES (
    v_gameya_id, v_family_id, 500, CURRENT_DATE, 'UPCOMING', 1
  );
  PERFORM set_config('role', 'authenticated', true);

  -- 3. Calculate safe-to-spend
  -- Initial balance: 10000
  -- Minus partial payment: 400
  -- Real wallet balance = 9600
  -- Commits remaining: 600
  -- Debt remaining: 2000
  -- Gameya remaining this cycle: 500
  -- Safe to spend = 9600 - 600 - 2000 - 500 = 6500
  v_safe_spend := public.fn_calculate_safe_to_spend(v_family_id);
  
  IF v_safe_spend != 6500 THEN
    RAISE EXCEPTION 'TEST FAILED: Safe to spend is %, expected 6500', v_safe_spend;
  END IF;

  -- Pay the remaining commitment
  PERFORM public.fn_pay_commitment_occurrence(v_family_id, v_occ_id, v_real_w, 600, now(), 'Test rest');
  IF (SELECT status FROM public.commitment_occurrences WHERE id = v_occ_id) != 'PAID' THEN
    RAISE EXCEPTION 'TEST FAILED: Occurrence not marked as PAID after paying remaining';
  END IF;

  -- Safe to spend should now be 6500 again (balance decreased by 600, but liability also decreased by 600)
  v_safe_spend := public.fn_calculate_safe_to_spend(v_family_id);
  IF v_safe_spend != 6500 THEN
    RAISE EXCEPTION 'TEST FAILED: Safe to spend after full payment is %, expected 6500', v_safe_spend;
  END IF;

  RAISE NOTICE 'ALL PHASE 4A TESTS PASSED SUCCESSFULLY!';
  
  -- Rollback is implicit or we can just rollback
  -- Actually, DO blocks don't need explicit rollback if we raise exception, but here we passed.
  -- To keep db clean, we can just raise an exception to rollback at the end.
  RAISE EXCEPTION 'SUCCESS_ROLLBACK'; 
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'SUCCESS_ROLLBACK' THEN
      RAISE NOTICE 'Rolled back test data successfully.';
    ELSE
      RAISE;
    END IF;
END $$;
