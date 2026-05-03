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
BEGIN
  RAISE NOTICE '--- Starting Mezan Atomic POSITIVE Tests ---';

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_id), true);
  
  INSERT INTO auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) 
  VALUES (v_user_id, 'authenticated', 'authenticated', 'testuser_' || gen_random_uuid() || '@example.com', 'password', now(), now());

  INSERT INTO public.family_groups (id, name) VALUES (v_family_id, 'Test Family');
  INSERT INTO public.family_members (id, family_id, user_id, role, status) VALUES (v_member_id, v_family_id, v_user_id, 'OWNER', 'ACTIVE');
  
  INSERT INTO public.categories (id, family_id, name_ar, name_en, direction, behavior) 
  VALUES (v_cat_income, v_family_id, 'مرتب اختبار', 'Test Salary', 'INCOME', 'SYSTEM');
  INSERT INTO public.categories (id, family_id, name_ar, name_en, direction, behavior) 
  VALUES (v_cat_expense, v_family_id, 'مصروف اختبار', 'Test Expense', 'EXPENSE', 'VARIABLE_BUDGETED');

  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_real_wallet, v_family_id, 'Cash', 'REAL', 0);
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_alloc_wallet_payout, v_family_id, 'Reserve Payout', 'ALLOCATED', 0);
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_alloc_wallet_installment, v_family_id, 'Reserve Installment', 'ALLOCATED', 0);
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_alloc_wallet_overfunded, v_family_id, 'Reserve Overfunded', 'ALLOCATED', 0);

  PERFORM public.fn_record_opening_balance(v_family_id, v_real_wallet, 1000);
  PERFORM public.fn_record_opening_balance(v_family_id, v_alloc_wallet_payout, 300);
  PERFORM public.fn_record_opening_balance(v_family_id, v_alloc_wallet_overfunded, 6000);

  -- Test 2: Failed RPC Rollback (Testing Application-Level Exceptions, not RLS)
  BEGIN
    PERFORM public.fn_record_expense(v_family_id, 2000, v_real_wallet, v_cat_expense, 'Test Overspend');
    RAISE EXCEPTION 'TEST_FAILED: Overspend should have failed.';
  EXCEPTION WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%INSUFFICIENT_BALANCE%' THEN
        RAISE EXCEPTION 'Unexpected error in Test 2: %', SQLERRM;
      END IF;
  END;

  -- Test 3: Debt Directions
  INSERT INTO public.debts (id, family_id, entity_name, direction, original_amount, remaining_amount, status) 
  VALUES (v_debt_borrowed, v_family_id, 'Uncle', 'BORROWED_FROM', 500, 500, 'ACTIVE');
  v_txn_id := public.fn_record_debt_payment(v_family_id, v_debt_borrowed, 100, v_real_wallet);
  
  INSERT INTO public.debts (id, family_id, entity_name, direction, original_amount, remaining_amount, status) 
  VALUES (v_debt_lent, v_family_id, 'Friend', 'LENT_TO', 500, 500, 'ACTIVE');
  v_txn_id := public.fn_record_debt_payment(v_family_id, v_debt_lent, 100, v_real_wallet);

  -- Test 4: Gameya Reconciliation
  INSERT INTO public.gameya_circles (id, family_id, name, monthly_installment, total_months, payout_month, status, wallet_id, start_date)
  VALUES (v_gameya_payout_id, v_family_id, 'Test Gameya Payout', 500, 10, 5, 'SAVING_PHASE', v_alloc_wallet_payout, current_date);
  SELECT reserve_transfer_txn_id, loan_receive_txn_id INTO v_txn_id, v_loan_id FROM public.fn_receive_gameya_payout(v_family_id, v_gameya_payout_id, v_real_wallet);

  -- Test 6: Opening Balance
  INSERT INTO public.wallets (id, family_id, name, type, balance) VALUES (v_new_wallet, v_family_id, 'New Wallet', 'REAL', 0);
  v_txn_id := public.fn_record_opening_balance(v_family_id, v_new_wallet, 1000);

  RAISE NOTICE '--- All Positive Integrity Tests Passed ---';
END $$;
ROLLBACK;
