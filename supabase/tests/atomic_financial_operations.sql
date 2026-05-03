-- =============================================================================
-- Mezan: atomic_financial_operations.sql
-- Verification tests for atomicity and financial integrity.
-- Usage: Execute this file manually via psql or Supabase SQL Editor.
-- =============================================================================

BEGIN; -- Start transaction for tests, we will rollback at the end

DO $$
DECLARE
  v_user_id UUID := gen_random_uuid();
  v_family_id UUID := gen_random_uuid();
  v_real_wallet UUID := gen_random_uuid();
  v_alloc_wallet UUID := gen_random_uuid();
  v_cat_income UUID := gen_random_uuid();
  v_cat_expense UUID := gen_random_uuid();
  
  v_debt_borrowed UUID := gen_random_uuid();
  v_debt_lent UUID := gen_random_uuid();
  v_gameya_payout_id UUID := gen_random_uuid();
  v_gameya_installment_id UUID := gen_random_uuid();
  v_gameya_overfunded_id UUID := gen_random_uuid();
  v_alloc_wallet_payout UUID := gen_random_uuid();
  v_alloc_wallet_installment UUID := gen_random_uuid();
  v_alloc_wallet_overfunded UUID := gen_random_uuid();
  
  v_member_id UUID := gen_random_uuid();
  v_turn_id UUID := gen_random_uuid();
  v_new_wallet UUID := gen_random_uuid();
  v_txn_id UUID;
  v_loan_id UUID;
  v_balance NUMERIC(14,2);
  v_reconciled NUMERIC(14,2);
BEGIN
  RAISE NOTICE '--- Starting Mezan Atomic Tests ---';

  -- 1. Setup Mock Environment (bypass RLS for setup, then test triggers/functions)
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_id), true);
  
  -- Create auth.users row to satisfy foreign key constraints
  INSERT INTO auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) 
  VALUES (v_user_id, 'authenticated', 'authenticated', 'testuser_' || gen_random_uuid() || '@example.com', 'password', now(), now());

  -- Insert dummy family (no cycle columns, just name)
  INSERT INTO public.family_groups (id, name) VALUES (v_family_id, 'Test Family');
  
  -- Insert dummy member to satisfy _require_member
  INSERT INTO public.family_members (id, family_id, user_id, role, status) VALUES (v_member_id, v_family_id, v_user_id, 'OWNER', 'ACTIVE');
  
  -- Insert valid categories to satisfy potential FKs
  INSERT INTO public.categories (id, family_id, name_ar, name_en, direction, behavior) 
  VALUES (v_cat_income, v_family_id, 'مرتب اختبار', 'Test Salary', 'INCOME', 'SYSTEM');
  INSERT INTO public.categories (id, family_id, name_ar, name_en, direction, behavior) 
  VALUES (v_cat_expense, v_family_id, 'مصروف اختبار', 'Test Expense', 'EXPENSE', 'VARIABLE_BUDGETED');

  -- Insert wallets
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_real_wallet, v_family_id, 'Cash', 'REAL', 0);
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_alloc_wallet_payout, v_family_id, 'Reserve Payout', 'ALLOCATED', 0);
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_alloc_wallet_installment, v_family_id, 'Reserve Installment', 'ALLOCATED', 0);
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_alloc_wallet_overfunded, v_family_id, 'Reserve Overfunded', 'ALLOCATED', 0);

  -- Set up initial balances securely through RPCs
  PERFORM public.fn_record_opening_balance(v_family_id, v_real_wallet, 1000);
  PERFORM public.fn_record_opening_balance(v_family_id, v_alloc_wallet_payout, 300);
  PERFORM public.fn_record_opening_balance(v_family_id, v_alloc_wallet_overfunded, 6000);

  -- ---------------------------------------------------------------------------
  -- Test 1: Direct Insert Blocked
  -- ---------------------------------------------------------------------------
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', v_user_id), true);
    INSERT INTO public.ledger_transactions(family_id,type,amount,to_wallet_id,created_by) 
    VALUES(v_family_id,'INCOME',100,v_real_wallet,v_member_id);
    RAISE EXCEPTION 'TEST_FAILED: Direct insert should be blocked by RLS.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLSTATE = '42501' THEN 
        RAISE NOTICE 'Test 1 Passed: Direct insert blocked by RLS (%).', SQLERRM;
      ELSE
        RAISE EXCEPTION 'Unexpected error in Test 1: %', SQLERRM;
      END IF;
  END;
  
  -- Reset role to postgres for remaining tests
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_id), true);

  -- ---------------------------------------------------------------------------
  -- Test 1.5: Direct Update of Derived Fields Blocked
  -- ---------------------------------------------------------------------------
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.wallets SET balance = 9999 WHERE id = v_real_wallet;
    RAISE EXCEPTION 'TEST_FAILED: Direct update of balance should be blocked by trigger.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%DIRECT_UPDATE_BLOCKED%' THEN
        RAISE EXCEPTION 'Unexpected error in Test 1.5 (wallet): %', SQLERRM;
      END IF;
  END;

  BEGIN
    INSERT INTO public.budgets (id, family_id, category_id, allocated_amount, spent_amount, period, cycle_start, cycle_end)
    VALUES (gen_random_uuid(), v_family_id, v_cat_expense, 1000, 0, 'MONTHLY', current_date, current_date + 30);
    
    SET LOCAL ROLE authenticated;
    UPDATE public.budgets SET spent_amount = 9999 WHERE family_id = v_family_id AND category_id = v_cat_expense;
    RAISE EXCEPTION 'TEST_FAILED: Direct update of budget should be blocked by trigger.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%DIRECT_UPDATE_BLOCKED%' THEN
        RAISE EXCEPTION 'Unexpected error in Test 1.5 (budget): %', SQLERRM;
      END IF;
  END;
  
  BEGIN
    INSERT INTO public.debts (id, family_id, entity_name, direction, original_amount, remaining_amount, created_by)
    VALUES (gen_random_uuid(), v_family_id, 'Test Entity', 'LENT_TO', 1000, 1000, v_member_id);
    
    SET LOCAL ROLE authenticated;
    UPDATE public.debts SET remaining_amount = 0 WHERE family_id = v_family_id;
    RAISE EXCEPTION 'TEST_FAILED: Direct update of debt should be blocked by trigger.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%DIRECT_UPDATE_BLOCKED%' THEN
        RAISE EXCEPTION 'Unexpected error in Test 1.5 (debt): %', SQLERRM;
      END IF;
  END;

  RAISE NOTICE 'Test 1.5 Passed: Direct update of derived fields blocked.';
  RESET ROLE;

  -- ---------------------------------------------------------------------------
  -- Test 2: Failed RPC Rollback
  -- ---------------------------------------------------------------------------
  BEGIN
    -- Try to spend 2000 from a wallet with 1000
    PERFORM public.fn_record_expense(v_family_id, 2000, v_real_wallet, v_cat_expense, 'Test Overspend');
    RAISE EXCEPTION 'TEST_FAILED: Overspend should have failed.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%INSUFFICIENT_BALANCE%' THEN
        RAISE NOTICE 'Test 2 Passed: Overspend Rolled Back (%).', SQLERRM;
      ELSE
        RAISE EXCEPTION 'Unexpected error in Test 2: %', SQLERRM;
      END IF;
  END;
  -- Verify wallet is untouched
  SELECT balance INTO v_balance FROM public.wallets WHERE id = v_real_wallet;
  IF v_balance != 1000 THEN RAISE EXCEPTION 'TEST_FAILED: Wallet balance changed after rollback.'; END IF;

  -- ---------------------------------------------------------------------------
  -- Test 3: Debt Directions
  -- ---------------------------------------------------------------------------
  -- 3a. BORROWED_FROM (We pay them, wallet decreases)
  INSERT INTO public.debts (id, family_id, entity_name, direction, original_amount, remaining_amount, status) 
  VALUES (v_debt_borrowed, v_family_id, 'Uncle', 'BORROWED_FROM', 500, 500, 'ACTIVE');
  
  v_txn_id := public.fn_record_debt_payment(v_family_id, v_debt_borrowed, 100, v_real_wallet);
  
  SELECT balance INTO v_balance FROM public.wallets WHERE id = v_real_wallet;
  IF v_balance != 900 THEN RAISE EXCEPTION 'TEST_FAILED: BORROWED_FROM payment did not decrease wallet. Balance: %', v_balance; END IF;
  
  -- 3b. LENT_TO (They pay us, wallet increases)
  INSERT INTO public.debts (id, family_id, entity_name, direction, original_amount, remaining_amount, status) 
  VALUES (v_debt_lent, v_family_id, 'Friend', 'LENT_TO', 500, 500, 'ACTIVE');
  
  v_txn_id := public.fn_record_debt_payment(v_family_id, v_debt_lent, 100, v_real_wallet);
  
  SELECT balance INTO v_balance FROM public.wallets WHERE id = v_real_wallet;
  IF v_balance != 1000 THEN RAISE EXCEPTION 'TEST_FAILED: LENT_TO payment did not increase wallet. Balance: %', v_balance; END IF;
  RAISE NOTICE 'Test 3 Passed: Both Debt Directions Handled Correctly.';

  -- ---------------------------------------------------------------------------
  -- Test 4: Gameya Reconciliation
  -- ---------------------------------------------------------------------------
  INSERT INTO public.gameya_circles (id, family_id, name, monthly_installment, total_months, payout_month, status, wallet_id, start_date)
  VALUES (v_gameya_payout_id, v_family_id, 'Test Gameya Payout', 500, 10, 5, 'SAVING_PHASE', v_alloc_wallet_payout, current_date);
  -- Gameya payout is 5000. Reserve has 300. Payout early.
  
  SELECT reserve_transfer_txn_id, loan_receive_txn_id 
  INTO v_txn_id, v_loan_id
  FROM public.fn_receive_gameya_payout(v_family_id, v_gameya_payout_id, v_real_wallet);
  
  -- Wallet should increase by 5000 -> 1000 + 5000 = 6000
  SELECT balance INTO v_balance FROM public.wallets WHERE id = v_real_wallet;
  IF v_balance != 6000 THEN RAISE EXCEPTION 'TEST_FAILED: Real wallet did not receive gameya payout correctly. Balance: %', v_balance; END IF;
  
  -- Reserve wallet should be 0
  SELECT balance INTO v_balance FROM public.wallets WHERE id = v_alloc_wallet_payout;
  IF v_balance != 0 THEN RAISE EXCEPTION 'TEST_FAILED: Reserve wallet not zeroed. Balance: %', v_balance; END IF;
  
  -- Reconcile reserve wallet to ensure ledger matches balance
  v_balance := public.fn_recalculate_wallet_balance(v_alloc_wallet_payout);
  IF v_balance != 0 THEN RAISE EXCEPTION 'TEST_FAILED: Gameya reserve ledger reconciliation is not 0. Got: %', v_balance; END IF;
  
  RAISE NOTICE 'Test 4 Passed: Gameya Payout + Reconciliation Successful.';

  -- ---------------------------------------------------------------------------
  -- Test 5: Correction Types Restrictions
  -- ---------------------------------------------------------------------------
  -- Create an INCOME
  v_txn_id := public.fn_record_income(v_family_id, 200, v_real_wallet, v_cat_income, 'Salary');
  -- Correct it
  PERFORM public.fn_correct_transaction(v_family_id, v_txn_id, 300, v_cat_income, 'Salary Corrected');
  RAISE NOTICE 'Test 5a Passed: INCOME corrected successfully.';
  
  -- Create a GAMEYA_PAYOUT (already done in Test 4, v_txn_id returned may not be exactly the payout, let's query it)
  SELECT id INTO v_txn_id FROM public.ledger_transactions WHERE type = 'GAMEYA_PAYOUT' LIMIT 1;
  
  BEGIN
    PERFORM public.fn_correct_transaction(v_family_id, v_txn_id, 1000);
    RAISE EXCEPTION 'TEST_FAILED: Should not allow correcting complex GAMEYA_PAYOUT transaction.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%CORRECTION_NOT_ALLOWED%' THEN
        RAISE NOTICE 'Test 5b Passed: Complex correction prevented.';
      ELSE
        RAISE EXCEPTION 'Unexpected error in Test 5b: %', SQLERRM;
      END IF;
  END;

  -- ---------------------------------------------------------------------------
  -- Test 6: Opening Balance + Reconciliation
  -- ---------------------------------------------------------------------------
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_new_wallet, v_family_id, 'New Wallet', 'REAL', 0);
  v_txn_id := public.fn_record_opening_balance(v_family_id, v_new_wallet, 1000);
  SELECT balance INTO v_balance FROM public.wallets WHERE id = v_new_wallet;
  IF v_balance != 1000 THEN RAISE EXCEPTION 'TEST_FAILED: Opening balance not applied.'; END IF;
  v_reconciled := public.fn_recalculate_wallet_balance(v_new_wallet);
  IF v_reconciled != 1000 THEN RAISE EXCEPTION 'TEST_FAILED: Opening balance reconciliation failed.'; END IF;
  RAISE NOTICE 'Test 6 Passed: Opening balance recorded and reconciled.';

  -- ---------------------------------------------------------------------------
  -- Test 7: Category Direction Mismatch
  -- ---------------------------------------------------------------------------
  BEGIN
    -- Try to record income using an expense category
    PERFORM public.fn_record_income(v_family_id, 100, v_real_wallet, v_cat_expense, 'Mismatch');
    RAISE EXCEPTION 'TEST_FAILED: Should block INCOME with EXPENSE category.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%INVALID_CATEGORY_DIRECTION%' THEN
        RAISE NOTICE 'Test 7 Passed: Category direction mismatch blocked.';
      ELSE
        RAISE EXCEPTION 'Unexpected error in Test 7: %', SQLERRM;
      END IF;
  END;

  -- ---------------------------------------------------------------------------
  -- Test 8: Gameya Installment Updates Turn
  -- ---------------------------------------------------------------------------
  INSERT INTO public.gameya_circles (id, family_id, name, monthly_installment, total_months, payout_month, status, wallet_id, start_date)
  VALUES (v_gameya_installment_id, v_family_id, 'Test Gameya Installment', 500, 10, 5, 'SAVING_PHASE', v_alloc_wallet_installment, current_date);
  
  INSERT INTO public.gameya_turns (id, gameya_id, family_id, turn_number, due_date) VALUES (v_turn_id, v_gameya_installment_id, v_family_id, 1, current_date);
  -- Gameya monthly installment is 500
  v_txn_id := public.fn_record_gameya_installment(v_family_id, v_turn_id, v_real_wallet);
  -- Check turn status
  IF NOT EXISTS (SELECT 1 FROM public.gameya_turns WHERE id = v_turn_id AND status = 'PAID' AND transaction_id = v_txn_id) THEN
    RAISE EXCEPTION 'TEST_FAILED: Gameya turn not updated properly.';
  END IF;
  RAISE NOTICE 'Test 8 Passed: Gameya installment recorded and turn updated.';

  -- ---------------------------------------------------------------------------
  -- Test 9: Correction Recalculation Integrity
  -- ---------------------------------------------------------------------------
  DECLARE
    v_balance_before NUMERIC(14,2);
  BEGIN
    -- Let's check current balance before any operations
    SELECT balance INTO v_balance_before FROM public.wallets WHERE id = v_real_wallet;
    
    -- Create new expense of 50
    v_txn_id := public.fn_record_expense(v_family_id, 50, v_real_wallet, v_cat_expense, 'To be corrected');
    
    -- Correct it to 60
    PERFORM public.fn_correct_transaction(v_family_id, v_txn_id, 60, v_cat_expense, 'Corrected');
    
    -- Run recalculation
    v_reconciled := public.fn_recalculate_wallet_balance(v_real_wallet);
    
    -- Check that the new balance exactly equals the pre-operation balance - 60
    SELECT balance INTO v_balance FROM public.wallets WHERE id = v_real_wallet;
    
    IF v_balance != (v_balance_before - 60) THEN 
      RAISE EXCEPTION 'TEST_FAILED: Balance after correction is wrong. Expected %, Got %', (v_balance_before - 60), v_balance; 
    END IF;
    
    IF v_balance != v_reconciled THEN 
      RAISE EXCEPTION 'TEST_FAILED: Post-correction reconciliation mismatch. Wallet: %, Ledger: %', v_balance, v_reconciled; 
    END IF;
    
    RAISE NOTICE 'Test 9 Passed: Correction maintains ledger integrity.';
  END;

  -- ---------------------------------------------------------------------------
  -- Test 10: Overfunded Gameya Rejected
  -- ---------------------------------------------------------------------------
  INSERT INTO public.gameya_circles (id, family_id, name, monthly_installment, total_months, payout_month, status, wallet_id, start_date)
  VALUES (v_gameya_overfunded_id, v_family_id, 'Test Gameya Overfunded', 500, 10, 5, 'SAVING_PHASE', v_alloc_wallet_overfunded, current_date);
  -- Reserve wallet has 6000 (setup in Test 1). Payout is 5000.
  
  -- Try to payout
  BEGIN
    PERFORM public.fn_receive_gameya_payout(v_family_id, v_gameya_overfunded_id, v_real_wallet);
    RAISE EXCEPTION 'TEST_FAILED: Overfunded reserve should block payout.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%GAMEYA_RESERVE_OVERFUNDED%' THEN
        RAISE NOTICE 'Test 10 Passed: Overfunded gameya payout blocked.';
      ELSE
        RAISE EXCEPTION 'Unexpected error in Test 10: %', SQLERRM;
      END IF;
  END;

  -- ---------------------------------------------------------------------------
  -- Test 11: Loan Disbursement and Receiving
  -- ---------------------------------------------------------------------------
  DECLARE
    v_balance_before NUMERIC(14,2);
  BEGIN
    SELECT balance INTO v_balance_before FROM public.wallets WHERE id = v_real_wallet;
    
    -- Disburse loan of 200 from Real Wallet
    SELECT * FROM public.fn_disburse_loan(v_family_id, 'Friend A', 200, v_real_wallet) INTO v_loan_id, v_txn_id;
    SELECT balance INTO v_balance FROM public.wallets WHERE id = v_real_wallet;
    IF v_balance != (v_balance_before - 200) THEN RAISE EXCEPTION 'TEST_FAILED: Disburse loan failed to deduct balance.'; END IF;
    
    -- Check debt record
    IF NOT EXISTS (SELECT 1 FROM public.debts WHERE id = v_loan_id AND direction = 'LENT_TO' AND remaining_amount = 200) THEN
      RAISE EXCEPTION 'TEST_FAILED: Debt record not created correctly for disburse.';
    END IF;

    SELECT balance INTO v_balance_before FROM public.wallets WHERE id = v_real_wallet;
    -- Receive loan of 300 to Real Wallet
    SELECT * FROM public.fn_receive_loan(v_family_id, 'Bank', 300, v_real_wallet) INTO v_loan_id, v_txn_id;
    SELECT balance INTO v_balance FROM public.wallets WHERE id = v_real_wallet;
    IF v_balance != (v_balance_before + 300) THEN RAISE EXCEPTION 'TEST_FAILED: Receive loan failed to add balance.'; END IF;

    -- Check debt record
    IF NOT EXISTS (SELECT 1 FROM public.debts WHERE id = v_loan_id AND direction = 'BORROWED_FROM' AND remaining_amount = 300) THEN
      RAISE EXCEPTION 'TEST_FAILED: Debt record not created correctly for receive.';
    END IF;
    
    RAISE NOTICE 'Test 11 Passed: Loan disburse and receive work correctly.';
  END;

  -- ---------------------------------------------------------------------------
  -- Test 12: SECURITY DEFINER Bypass Test
  -- ---------------------------------------------------------------------------
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', v_user_id), true);
    
    -- Attempt to record income via RPC (runs as SECURITY DEFINER postgres)
    v_txn_id := public.fn_record_income(v_family_id, 100, v_real_wallet, v_cat_income, 'Test Bypass');
    
    RAISE NOTICE 'Test 12 Passed: SECURITY DEFINER RPC successfully bypassed the trigger.';
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'TEST_FAILED: RPC failed under authenticated role, SECURITY DEFINER bypass might be broken. Error: %', SQLERRM;
  END;
  RESET ROLE;

  RAISE NOTICE '--- All Integrity Tests Passed ---';

END $$;

ROLLBACK; -- Undo all test data insertions
