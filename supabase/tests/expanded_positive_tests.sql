BEGIN;
DO $$
DECLARE
  v_user_id UUID := gen_random_uuid();
  v_family_id UUID := gen_random_uuid();
  v_real_wallet UUID := gen_random_uuid();
  v_alloc_wallet_payout UUID := gen_random_uuid();
  v_alloc_wallet_installment UUID := gen_random_uuid();
  v_alloc_wallet_overfunded UUID := gen_random_uuid();
  v_cat_income UUID := gen_random_uuid();
  v_cat_expense UUID := gen_random_uuid();
  
  v_debt_borrowed UUID := gen_random_uuid();
  v_debt_lent UUID := gen_random_uuid();
  v_gameya_payout_id UUID := gen_random_uuid();
  v_gameya_installment_id UUID := gen_random_uuid();
  v_gameya_overfunded_id UUID := gen_random_uuid();
  
  v_member_id UUID := gen_random_uuid();
  v_turn_id UUID := gen_random_uuid();
  v_new_wallet UUID := gen_random_uuid();
  v_txn_id UUID;
  v_loan_id UUID;
  v_balance NUMERIC(14,2);
  v_reconciled NUMERIC(14,2);
  v_balance_before NUMERIC(14,2);
BEGIN
  RAISE NOTICE '--- Starting Mezan Expanded Atomic POSITIVE Tests ---';

  -- Setup
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_id), true);
  INSERT INTO auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) 
  VALUES (v_user_id, 'authenticated', 'authenticated', 'testuser_' || gen_random_uuid() || '@example.com', 'password', now(), now());
  INSERT INTO public.family_groups (id, name) VALUES (v_family_id, 'Test Family');
  INSERT INTO public.family_members (id, family_id, user_id, role, status) VALUES (v_member_id, v_family_id, v_user_id, 'OWNER', 'ACTIVE');
  
  INSERT INTO public.categories (id, family_id, name_ar, name_en, direction, behavior) VALUES (v_cat_income, v_family_id, 'مرتب', 'Salary', 'INCOME', 'SYSTEM');
  INSERT INTO public.categories (id, family_id, name_ar, name_en, direction, behavior) VALUES (v_cat_expense, v_family_id, 'مصروف', 'Expense', 'EXPENSE', 'VARIABLE_BUDGETED');

  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_real_wallet, v_family_id, 'Cash', 'REAL', 0);
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_alloc_wallet_payout, v_family_id, 'Reserve Payout', 'ALLOCATED', 0);
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_alloc_wallet_installment, v_family_id, 'Reserve Installment', 'ALLOCATED', 0);
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_alloc_wallet_overfunded, v_family_id, 'Reserve Overfunded', 'ALLOCATED', 0);

  PERFORM public.fn_record_opening_balance(v_family_id, v_real_wallet, 1000);
  PERFORM public.fn_record_opening_balance(v_family_id, v_alloc_wallet_payout, 300);
  PERFORM public.fn_record_opening_balance(v_family_id, v_alloc_wallet_overfunded, 6000);

  -- 1. Test Debt Payment Directions
  INSERT INTO public.debts (id, family_id, entity_name, direction, original_amount, remaining_amount, status) VALUES (v_debt_borrowed, v_family_id, 'Uncle', 'BORROWED_FROM', 500, 500, 'ACTIVE');
  SELECT balance INTO v_balance_before FROM public.wallets WHERE id = v_real_wallet;
  PERFORM public.fn_record_debt_payment(v_family_id, v_debt_borrowed, 100, v_real_wallet);
  SELECT balance INTO v_balance FROM public.wallets WHERE id = v_real_wallet;
  IF v_balance != (v_balance_before - 100) THEN RAISE EXCEPTION 'Assertion Failed: BORROWED_FROM payment did not decrease balance.'; END IF;

  INSERT INTO public.debts (id, family_id, entity_name, direction, original_amount, remaining_amount, status) VALUES (v_debt_lent, v_family_id, 'Friend', 'LENT_TO', 500, 500, 'ACTIVE');
  SELECT balance INTO v_balance_before FROM public.wallets WHERE id = v_real_wallet;
  PERFORM public.fn_record_debt_payment(v_family_id, v_debt_lent, 100, v_real_wallet);
  SELECT balance INTO v_balance FROM public.wallets WHERE id = v_real_wallet;
  IF v_balance != (v_balance_before + 100) THEN RAISE EXCEPTION 'Assertion Failed: LENT_TO payment did not increase balance.'; END IF;

  -- 2. Test Gameya Payout Zeroes Wallet
  INSERT INTO public.gameya_circles (id, family_id, name, monthly_installment, total_months, payout_month, status, wallet_id, start_date)
  VALUES (v_gameya_payout_id, v_family_id, 'Payout', 500, 10, 5, 'SAVING_PHASE', v_alloc_wallet_payout, current_date);
  PERFORM public.fn_receive_gameya_payout(v_family_id, v_gameya_payout_id, v_real_wallet);
  SELECT balance INTO v_balance FROM public.wallets WHERE id = v_alloc_wallet_payout;
  IF v_balance != 0 THEN RAISE EXCEPTION 'Assertion Failed: Gameya payout did not zero the allocated wallet.'; END IF;

  -- 3. Test fn_recalculate_wallet_balance Matches
  v_reconciled := public.fn_recalculate_wallet_balance(v_alloc_wallet_payout);
  IF v_reconciled != 0 THEN RAISE EXCEPTION 'Assertion Failed: Recalculation of payout wallet is not 0.'; END IF;

  -- 4. Test Opening Balance
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_new_wallet, v_family_id, 'New Wallet', 'REAL', 0);
  PERFORM public.fn_record_opening_balance(v_family_id, v_new_wallet, 1500);
  SELECT balance INTO v_balance FROM public.wallets WHERE id = v_new_wallet;
  IF v_balance != 1500 THEN RAISE EXCEPTION 'Assertion Failed: Opening balance not recorded correctly.'; END IF;
  v_reconciled := public.fn_recalculate_wallet_balance(v_new_wallet);
  IF v_reconciled != 1500 THEN RAISE EXCEPTION 'Assertion Failed: Opening balance reconciliation failed.'; END IF;

  -- 5. Test Gameya Installment and update gameya_turns
  INSERT INTO public.gameya_circles (id, family_id, name, monthly_installment, total_months, payout_month, status, wallet_id, start_date)
  VALUES (v_gameya_installment_id, v_family_id, 'Installment', 500, 10, 5, 'SAVING_PHASE', v_alloc_wallet_installment, current_date);
  INSERT INTO public.gameya_turns (id, gameya_id, family_id, turn_number, due_date) VALUES (v_turn_id, v_gameya_installment_id, v_family_id, 1, current_date);
  SELECT balance INTO v_balance_before FROM public.wallets WHERE id = v_real_wallet;
  v_txn_id := public.fn_record_gameya_installment(v_family_id, v_turn_id, v_real_wallet);
  SELECT balance INTO v_balance FROM public.wallets WHERE id = v_real_wallet;
  IF v_balance != (v_balance_before - 500) THEN RAISE EXCEPTION 'Assertion Failed: Installment did not decrease real wallet.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.gameya_turns WHERE id = v_turn_id AND status = 'PAID' AND transaction_id = v_txn_id) THEN
    RAISE EXCEPTION 'Assertion Failed: Turn not marked as PAID with correct txn_id.';
  END IF;

  -- 6. Test Correction Recalculation Integrity
  SELECT balance INTO v_balance_before FROM public.wallets WHERE id = v_real_wallet;
  v_txn_id := public.fn_record_expense(v_family_id, 50, v_real_wallet, v_cat_expense, 'To be corrected');
  PERFORM public.fn_correct_transaction(v_family_id, v_txn_id, 60, v_cat_expense, 'Corrected');
  SELECT balance INTO v_balance FROM public.wallets WHERE id = v_real_wallet;
  IF v_balance != (v_balance_before - 60) THEN RAISE EXCEPTION 'Assertion Failed: Balance after correction is wrong. Expected %, Got %', (v_balance_before - 60), v_balance; END IF;
  v_reconciled := public.fn_recalculate_wallet_balance(v_real_wallet);
  IF v_balance != v_reconciled THEN RAISE EXCEPTION 'Assertion Failed: Post-correction reconciliation mismatch.'; END IF;

  -- 7. Test Overfunded Gameya
  INSERT INTO public.gameya_circles (id, family_id, name, monthly_installment, total_months, payout_month, status, wallet_id, start_date)
  VALUES (v_gameya_overfunded_id, v_family_id, 'Overfunded', 500, 10, 5, 'SAVING_PHASE', v_alloc_wallet_overfunded, current_date);
  BEGIN
    PERFORM public.fn_receive_gameya_payout(v_family_id, v_gameya_overfunded_id, v_real_wallet);
    RAISE EXCEPTION 'Assertion Failed: Overfunded reserve should block payout.';
  EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%GAMEYA_RESERVE_OVERFUNDED%' THEN
        RAISE EXCEPTION 'Unexpected error in overfunded test: %', SQLERRM;
      END IF;
  END;

  -- 8. Test Category Mismatch
  BEGIN
    PERFORM public.fn_record_income(v_family_id, 100, v_real_wallet, v_cat_expense, 'Mismatch');
    RAISE EXCEPTION 'Assertion Failed: Should block INCOME with EXPENSE category.';
  EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%INVALID_CATEGORY_DIRECTION%' THEN
        RAISE EXCEPTION 'Unexpected error in mismatch test: %', SQLERRM;
      END IF;
  END;

  RAISE NOTICE '--- All Expanded Positive & Logical Negative Tests Passed ---';
END $$;
ROLLBACK;
