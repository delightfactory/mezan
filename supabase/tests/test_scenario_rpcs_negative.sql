-- =============================================================================
-- test_scenario_rpcs_negative.sql
-- Plain SQL tests with full isolation and strict assertions (Testing Rollbacks)
-- =============================================================================

DO $$
DECLARE
  v_user_id UUID := gen_random_uuid();
  v_family_id UUID;
  v_member_id UUID;
  v_expense_cat_id UUID;
  v_income_cat_id UUID;
  v_real_wallet_id UUID;
  v_budget_id UUID;
  v_commitment_id UUID;
  v_occ_id UUID;
  v_txn_id UUID;
  v_bal NUMERIC;
  v_spent NUMERIC;
BEGIN
  -- 1. Setup Isolated Environment
  INSERT INTO auth.users (id, email) VALUES (v_user_id, 'test_neg_' || v_user_id || '@example.com');
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);
  PERFORM set_config('role', 'authenticated', true);

  SELECT family_id, member_id INTO v_family_id, v_member_id 
  FROM public.fn_create_initial_family('Test Negative Family', 'Test Owner');

  SELECT id INTO v_expense_cat_id FROM public.categories WHERE direction = 'EXPENSE' AND family_id IS NULL LIMIT 1;
  SELECT id INTO v_income_cat_id FROM public.categories WHERE direction = 'INCOME' AND family_id IS NULL LIMIT 1;

  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (v_family_id, 'Test Neg Wallet', 'REAL', 1000.00, v_member_id)
  RETURNING id INTO v_real_wallet_id;

  -- 2. Gameya: Negative Installment
  BEGIN
    PERFORM public.fn_create_gameya_circle(
      v_family_id, 'صندوق جمعية: Negative Gameya', -100.00, 10, 5, CURRENT_DATE
    );
    RAISE EXCEPTION 'TEST_FAILED: Gameya created with negative installment';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%GAMEYA_INVALID_CONFIG%' THEN RAISE; END IF;
  END;

  -- Check rollbacks explicitly
  IF EXISTS (SELECT 1 FROM public.gameya_circles WHERE name = 'صندوق جمعية: Negative Gameya') THEN RAISE EXCEPTION 'TEST_FAILED: Rollback failed for Negative Gameya circle'; END IF;
  IF EXISTS (SELECT 1 FROM public.wallets WHERE name = 'صندوق جمعية: Negative Gameya') THEN RAISE EXCEPTION 'TEST_FAILED: Rollback failed for Negative Gameya wallet'; END IF;
  IF EXISTS (SELECT 1 FROM public.gameya_turns t JOIN public.gameya_circles c ON t.gameya_id = c.id WHERE c.name = 'صندوق جمعية: Negative Gameya') THEN RAISE EXCEPTION 'TEST_FAILED: Rollback failed for Negative Gameya turns'; END IF;

  -- 3. Budget: Overlapping Dates (Duplicate)
  v_budget_id := public.fn_create_budget(
    v_family_id, v_expense_cat_id, '2050-01-01'::DATE, '2050-01-31'::DATE, 5000.00, 'MONTHLY'::public.budget_period
  );
  
  BEGIN
    PERFORM public.fn_create_budget(
      v_family_id, v_expense_cat_id, '2050-01-01'::DATE, '2050-01-31'::DATE, 6000.00, 'MONTHLY'::public.budget_period
    );
    RAISE EXCEPTION 'TEST_FAILED: Duplicate budget allowed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%DUPLICATE_BUDGET%' THEN RAISE; END IF;
  END;

  -- Check count = 1
  IF (SELECT count(*) FROM public.budgets WHERE family_id = v_family_id AND category_id = v_expense_cat_id AND cycle_start = '2050-01-01'::DATE) != 1 THEN
    RAISE EXCEPTION 'TEST_FAILED: Duplicate budget rollback failed';
  END IF;

  -- 4. Commitment: Invalid category (INCOME)
  BEGIN
    PERFORM public.fn_create_commitment(
      v_family_id, 'Income Commitment', v_income_cat_id, 1500.00, 'MONTHLY'::public.commitment_freq, CURRENT_DATE
    );
    RAISE EXCEPTION 'TEST_FAILED: Commitment created with INCOME category';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INVALID_CATEGORY_DIRECTION%' THEN RAISE; END IF;
  END;
  
  IF EXISTS (SELECT 1 FROM public.commitments WHERE name = 'Income Commitment') THEN RAISE EXCEPTION 'TEST_FAILED: Rollback failed for Income Commitment'; END IF;
  IF EXISTS (SELECT 1 FROM public.commitment_occurrences o JOIN public.commitments c ON o.commitment_id = c.id WHERE c.name = 'Income Commitment') THEN RAISE EXCEPTION 'TEST_FAILED: Rollback failed for Income Commitment occurrences'; END IF;

  -- 5. Payment: Insufficient Balance
  v_commitment_id := public.fn_create_commitment(
    v_family_id, 'Valid Commitment', v_expense_cat_id, 5000.00, 'ONE_TIME'::public.commitment_freq, CURRENT_DATE
  );
  SELECT id INTO v_occ_id FROM public.commitment_occurrences WHERE commitment_id = v_commitment_id LIMIT 1;

  BEGIN
    PERFORM public.fn_pay_commitment_occurrence(v_family_id, v_occ_id, v_real_wallet_id, CURRENT_DATE, 'Test Payment');
    RAISE EXCEPTION 'TEST_FAILED: Payment succeeded with insufficient balance';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INSUFFICIENT_BALANCE%' THEN RAISE; END IF;
  END;

  -- Verify no side effects
  SELECT balance INTO v_bal FROM public.wallets WHERE id = v_real_wallet_id;
  IF v_bal != 1000.00 THEN RAISE EXCEPTION 'TEST_FAILED: Wallet balance changed on failed payment'; END IF;

  IF (SELECT status FROM public.commitment_occurrences WHERE id = v_occ_id) != 'UPCOMING' THEN RAISE EXCEPTION 'TEST_FAILED: Occurrence status changed on failed payment'; END IF;
  IF (SELECT paid_transaction_id FROM public.commitment_occurrences WHERE id = v_occ_id) IS NOT NULL THEN RAISE EXCEPTION 'TEST_FAILED: Occurrence paid_transaction_id not null on failed payment'; END IF;
  
  IF EXISTS (SELECT 1 FROM public.ledger_transactions WHERE description LIKE '%Valid Commitment%') THEN RAISE EXCEPTION 'TEST_FAILED: Ledger transaction created on failed payment'; END IF;

  -- Check budget spent_amount unchanged
  v_budget_id := public.fn_create_budget(v_family_id, v_expense_cat_id, (CURRENT_DATE - interval '1 day')::DATE, (CURRENT_DATE + interval '30 days')::DATE, 5000.00, 'MONTHLY'::public.budget_period);
  SELECT spent_amount INTO v_spent FROM public.budgets WHERE id = v_budget_id;
  IF v_spent != 0 THEN RAISE EXCEPTION 'TEST_FAILED: Budget spent_amount changed on failed payment'; END IF;

  -- 6. Payment: Double Payment
  -- Create a fresh REAL wallet explicitly for this scenario with enough balance via opening balance RPC
  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (v_family_id, 'Double Payment Wallet', 'REAL', 0, v_member_id)
  RETURNING id INTO v_real_wallet_id;
  
  PERFORM public.fn_record_opening_balance(v_family_id, v_real_wallet_id, 10000.00);
  
  -- First payment
  v_txn_id := public.fn_pay_commitment_occurrence(v_family_id, v_occ_id, v_real_wallet_id, CURRENT_DATE, 'First Payment');
  
  -- Second payment
  BEGIN
    PERFORM public.fn_pay_commitment_occurrence(v_family_id, v_occ_id, v_real_wallet_id, CURRENT_DATE, 'Second Payment');
    RAISE EXCEPTION 'TEST_FAILED: Double payment succeeded';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%OCCURRENCE_NOT_PAYABLE%' THEN RAISE; END IF;
  END;

  -- Verify exactly one transaction exists, specifically using paid_transaction_id logic
  IF (SELECT count(*) FROM public.ledger_transactions WHERE id = v_txn_id) != 1 THEN
    RAISE EXCEPTION 'TEST_FAILED: Initial transaction not found';
  END IF;
  
  -- The description generated by the RPC should be 'دفع التزام: Valid Commitment'
  IF (SELECT count(*) FROM public.ledger_transactions WHERE family_id = v_family_id AND description = 'دفع التزام: Valid Commitment') != 1 THEN
    RAISE EXCEPTION 'TEST_FAILED: Double payment created extra transaction';
  END IF;

  -- Cleanup auth mock
  PERFORM set_config('role', 'postgres', true);

  RAISE EXCEPTION 'TEST_SUCCESS_ROLLBACK';
EXCEPTION
  WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    
    IF SQLERRM = 'TEST_SUCCESS_ROLLBACK' THEN
      RAISE NOTICE 'All negative tests passed! (Errors caught and rollbacks verified)';
    ELSE
      RAISE;
    END IF;
END $$;
