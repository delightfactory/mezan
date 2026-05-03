-- =============================================================================
-- test_scenario_rpcs_positive.sql
-- Plain SQL tests with full isolation and strict assertions
-- =============================================================================

DO $$
DECLARE
  v_user_id UUID := gen_random_uuid();
  v_family_id UUID;
  v_member_id UUID;
  v_expense_cat_id UUID;
  v_real_wallet_id UUID;
  v_alloc_wallet_id UUID;
  v_gameya_id UUID;
  v_budget_id UUID;
  v_commitment_id UUID;
  v_occ_id UUID;
  v_txn_id UUID;
  v_safe NUMERIC;
  v_real_bal NUMERIC;
  v_alloc_bal NUMERIC;
BEGIN
  -- 1. Setup Isolated Environment
  -- Create auth user
  INSERT INTO auth.users (id, email) VALUES (v_user_id, 'test_' || v_user_id || '@example.com');
  
  -- Set auth context
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);
  PERFORM set_config('role', 'authenticated', true);

  -- Create family using onboarding RPC
  SELECT family_id, member_id INTO v_family_id, v_member_id 
  FROM public.fn_create_initial_family('Test Positive Family', 'Test Owner');

  -- Get system categories
  SELECT id INTO v_expense_cat_id FROM public.categories WHERE direction = 'EXPENSE' AND family_id IS NULL LIMIT 1;
  IF v_expense_cat_id IS NULL THEN
    RAISE EXCEPTION 'TEST_FAILED: No system EXPENSE category found';
  END IF;

  -- Create a REAL wallet and an ALLOCATED wallet (balance 0)
  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (v_family_id, 'Test Real Wallet', 'REAL', 0, v_member_id)
  RETURNING id INTO v_real_wallet_id;

  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (v_family_id, 'Test Emergency Allocated', 'ALLOCATED', 0, v_member_id)
  RETURNING id INTO v_alloc_wallet_id;

  -- 2. Test Safe to Spend double deduction fix
  -- Add opening balance of 20000 to REAL wallet
  PERFORM public.fn_record_opening_balance(v_family_id, v_real_wallet_id, 20000.00);
  
  -- Verify safe to spend before transfer
  v_safe := public.fn_calculate_safe_to_spend(v_family_id);
  IF v_safe != 20000.00 THEN
    RAISE EXCEPTION 'TEST_FAILED: Safe to spend before transfer is wrong. Expected 20000, got %', v_safe;
  END IF;

  -- Transfer 2000 to ALLOCATED
  PERFORM public.fn_transfer_between_wallets(v_family_id, 2000.00, v_real_wallet_id, v_alloc_wallet_id, NULL, 'Emergency Transfer');
  
  -- Verify balances
  SELECT balance INTO v_real_bal FROM public.wallets WHERE id = v_real_wallet_id;
  SELECT balance INTO v_alloc_bal FROM public.wallets WHERE id = v_alloc_wallet_id;
  IF v_real_bal != 18000.00 THEN RAISE EXCEPTION 'TEST_FAILED: Real wallet balance not 18000, got %', v_real_bal; END IF;
  IF v_alloc_bal != 2000.00 THEN RAISE EXCEPTION 'TEST_FAILED: Alloc wallet balance not 2000, got %', v_alloc_bal; END IF;

  -- Verify safe to spend AFTER transfer
  -- Should be 18000. The 2000 in ALLOCATED should NOT be deducted again.
  v_safe := public.fn_calculate_safe_to_spend(v_family_id);
  IF v_safe != 18000.00 THEN
    RAISE EXCEPTION 'TEST_FAILED: Safe to spend double deduction bug exists! Expected 18000, got %', v_safe;
  END IF;

  -- 3. Gameya creation positive test
  v_gameya_id := public.fn_create_gameya_circle(
    v_family_id,
    'صندوق جمعية: Positive Gameya',
    1000.00,
    10,
    5,
    CURRENT_DATE
  );

  IF NOT EXISTS (SELECT 1 FROM public.gameya_circles WHERE id = v_gameya_id) THEN
    RAISE EXCEPTION 'TEST_FAILED: Gameya circle not created';
  END IF;

  IF (SELECT count(*) FROM public.gameya_turns WHERE gameya_id = v_gameya_id) != 10 THEN
    RAISE EXCEPTION 'TEST_FAILED: Gameya turns not generated correctly';
  END IF;

  -- 4. Budget creation positive test
  v_budget_id := public.fn_create_budget(
    v_family_id,
    v_expense_cat_id,
    CURRENT_DATE,
    (CURRENT_DATE + interval '30 days')::DATE,
    5000.00,
    'MONTHLY'::public.budget_period
  );

  IF NOT EXISTS (SELECT 1 FROM public.budgets WHERE id = v_budget_id) THEN
    RAISE EXCEPTION 'TEST_FAILED: Budget not created';
  END IF;

  -- 5. Commitment creation & payment
  v_commitment_id := public.fn_create_commitment(
    v_family_id,
    'Positive Commitment',
    v_expense_cat_id,
    1500.00,
    'MONTHLY'::public.commitment_freq,
    CURRENT_DATE,
    NULL,
    v_real_wallet_id,
    10,
    false
  );

  IF NOT EXISTS (SELECT 1 FROM public.commitments WHERE id = v_commitment_id) THEN
    RAISE EXCEPTION 'TEST_FAILED: Commitment not created';
  END IF;

  IF (SELECT count(*) FROM public.commitment_occurrences WHERE commitment_id = v_commitment_id) != 12 THEN
    RAISE EXCEPTION 'TEST_FAILED: Commitment occurrences not exactly 12 for MONTHLY';
  END IF;

  -- Test Payment
  SELECT id INTO v_occ_id FROM public.commitment_occurrences WHERE commitment_id = v_commitment_id AND status = 'UPCOMING' ORDER BY due_date ASC LIMIT 1;
  
  v_txn_id := public.fn_pay_commitment_occurrence(
    v_family_id,
    v_occ_id,
    v_real_wallet_id,
    CURRENT_DATE,
    'Test Payment'
  );

  IF NOT EXISTS (SELECT 1 FROM public.ledger_transactions WHERE id = v_txn_id AND type = 'EXPENSE') THEN
    RAISE EXCEPTION 'TEST_FAILED: Payment ledger transaction not created';
  END IF;

  IF (SELECT status FROM public.commitment_occurrences WHERE id = v_occ_id) != 'PAID' THEN
    RAISE EXCEPTION 'TEST_FAILED: Occurrence status not updated to PAID';
  END IF;

  -- Check wallet deduction (Original was 20000, then 2000 transferred = 18000. Then paid 1500 = 16500)
  SELECT balance INTO v_real_bal FROM public.wallets WHERE id = v_real_wallet_id;
  IF v_real_bal != 16500.00 THEN
    RAISE EXCEPTION 'TEST_FAILED: Wallet balance not deducted correctly. Expected 16500, got %', v_real_bal;
  END IF;

  -- Check budget spent amount incremented
  IF (SELECT spent_amount FROM public.budgets WHERE id = v_budget_id) != 1500.00 THEN
    RAISE EXCEPTION 'TEST_FAILED: Budget spent_amount not updated correctly';
  END IF;

  -- Cleanup auth mock
  PERFORM set_config('role', 'postgres', true);

  -- Rollback all test data
  RAISE EXCEPTION 'TEST_SUCCESS_ROLLBACK';
EXCEPTION
  WHEN OTHERS THEN
    -- Cleanup auth mock on failure just in case
    PERFORM set_config('role', 'postgres', true);
    
    IF SQLERRM = 'TEST_SUCCESS_ROLLBACK' THEN
      RAISE NOTICE 'All positive tests passed! (Rolled back to keep DB clean)';
    ELSE
      -- Re-raise immediately, NO silently passing or skipping!
      RAISE;
    END IF;
END $$;
