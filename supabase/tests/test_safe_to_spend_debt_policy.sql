-- =============================================================================
-- test_safe_to_spend_debt_policy.sql
-- Isolated tests for debt deduction policy from safe_to_spend
-- =============================================================================

DO $$
DECLARE
  v_user_id UUID := gen_random_uuid();
  v_family_id UUID;
  v_member_id UUID;
  v_real_wallet_id UUID;
  v_safe NUMERIC;
  v_debt_id UUID;
  v_end_of_month DATE;
BEGIN
  -- 1. Setup Isolated Environment
  INSERT INTO auth.users (id, email) VALUES (v_user_id, 'test_debt_' || v_user_id || '@example.com');
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);
  PERFORM set_config('role', 'authenticated', true);

  SELECT family_id, member_id INTO v_family_id, v_member_id 
  FROM public.fn_create_initial_family('Test Debt Policy Family', 'Test Owner');

  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (v_family_id, 'Test Real Wallet', 'REAL', 0, v_member_id)
  RETURNING id INTO v_real_wallet_id;

  -- Add 20000 to REAL wallet
  PERFORM public.fn_record_opening_balance(v_family_id, v_real_wallet_id, 20000.00);
  
  v_end_of_month := (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date;

  -- Verify initial safe_to_spend
  v_safe := public.fn_calculate_safe_to_spend(v_family_id);
  IF v_safe != 20000.00 THEN RAISE EXCEPTION 'TEST_FAILED: Initial safe_to_spend wrong'; END IF;

  -- 2. Scenario 1: Unscheduled borrowed debt
  -- remaining_amount = 2000, monthly_installment = NULL, due_date = NULL
  -- Expected: does NOT reduce safe_to_spend
  INSERT INTO public.debts (family_id, entity_name, direction, original_amount, remaining_amount, monthly_installment, due_date, status, created_by)
  VALUES (v_family_id, 'Scenario 1', 'BORROWED_FROM', 2000.00, 2000.00, NULL, NULL, 'ACTIVE', v_member_id)
  RETURNING id INTO v_debt_id;

  v_safe := public.fn_calculate_safe_to_spend(v_family_id);
  IF v_safe != 20000.00 THEN RAISE EXCEPTION 'TEST_FAILED: Unscheduled debt reduced safe_to_spend'; END IF;
  
  -- Cleanup Scenario 1
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.debts WHERE id = v_debt_id;
  PERFORM set_config('role', 'authenticated', true);

  -- 3. Scenario 2: Monthly installment borrowed debt
  -- remaining_amount = 2000, monthly_installment = 500
  -- Expected: reduces safe_to_spend by 500 only
  INSERT INTO public.debts (family_id, entity_name, direction, original_amount, remaining_amount, monthly_installment, due_date, status, created_by)
  VALUES (v_family_id, 'Scenario 2', 'BORROWED_FROM', 2000.00, 2000.00, 500.00, NULL, 'ACTIVE', v_member_id)
  RETURNING id INTO v_debt_id;

  v_safe := public.fn_calculate_safe_to_spend(v_family_id);
  IF v_safe != 19500.00 THEN RAISE EXCEPTION 'TEST_FAILED: Monthly installment debt did not reduce safe_to_spend correctly. Expected 19500, got %', v_safe; END IF;
  
  -- Cleanup Scenario 2
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.debts WHERE id = v_debt_id;
  PERFORM set_config('role', 'authenticated', true);

  -- 4. Scenario 3: Due borrowed debt this month
  -- remaining_amount = 2000, monthly_installment = NULL, due_date <= end_of_current_month
  -- Expected: reduces safe_to_spend by 2000
  INSERT INTO public.debts (family_id, entity_name, direction, original_amount, remaining_amount, monthly_installment, due_date, status, created_by)
  VALUES (v_family_id, 'Scenario 3', 'BORROWED_FROM', 2000.00, 2000.00, NULL, v_end_of_month, 'ACTIVE', v_member_id)
  RETURNING id INTO v_debt_id;

  v_safe := public.fn_calculate_safe_to_spend(v_family_id);
  IF v_safe != 18000.00 THEN RAISE EXCEPTION 'TEST_FAILED: Due debt this month did not reduce safe_to_spend correctly. Expected 18000, got %', v_safe; END IF;
  
  -- Cleanup Scenario 3
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.debts WHERE id = v_debt_id;
  PERFORM set_config('role', 'authenticated', true);

  -- 5. Scenario 4: Due borrowed debt in future month
  -- remaining_amount = 2000, monthly_installment = NULL, due_date after current month
  -- Expected: does NOT reduce current safe_to_spend
  INSERT INTO public.debts (family_id, entity_name, direction, original_amount, remaining_amount, monthly_installment, due_date, status, created_by)
  VALUES (v_family_id, 'Scenario 4', 'BORROWED_FROM', 2000.00, 2000.00, NULL, v_end_of_month + interval '10 days', 'ACTIVE', v_member_id)
  RETURNING id INTO v_debt_id;

  v_safe := public.fn_calculate_safe_to_spend(v_family_id);
  IF v_safe != 20000.00 THEN RAISE EXCEPTION 'TEST_FAILED: Future due debt reduced safe_to_spend incorrectly. Expected 20000, got %', v_safe; END IF;
  
  -- Cleanup Scenario 4
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.debts WHERE id = v_debt_id;
  PERFORM set_config('role', 'authenticated', true);

  -- 6. Scenario 5: Edge case: monthly installment > remaining amount
  -- Expected: reduces safe_to_spend by remaining_amount
  INSERT INTO public.debts (family_id, entity_name, direction, original_amount, remaining_amount, monthly_installment, due_date, status, created_by)
  VALUES (v_family_id, 'Scenario 5', 'BORROWED_FROM', 2000.00, 300.00, 500.00, NULL, 'ACTIVE', v_member_id)
  RETURNING id INTO v_debt_id;

  v_safe := public.fn_calculate_safe_to_spend(v_family_id);
  IF v_safe != 19700.00 THEN RAISE EXCEPTION 'TEST_FAILED: Edge case (installment > remaining) failed. Expected 19700, got %', v_safe; END IF;

  -- Cleanup auth mock
  PERFORM set_config('role', 'postgres', true);

  -- Rollback
  RAISE EXCEPTION 'TEST_SUCCESS_ROLLBACK';
EXCEPTION
  WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    IF SQLERRM = 'TEST_SUCCESS_ROLLBACK' THEN
      RAISE NOTICE 'All Debt Policy Tests passed!';
    ELSE
      RAISE;
    END IF;
END $$;
