-- =============================================================================
-- Mezan: test_flexible_gameya_exit_positive.sql
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_user_id UUID := gen_random_uuid();
  v_family_id UUID;
  v_member_id UUID;
  v_real_wallet_id UUID;
  v_gameya_id UUID;
  v_inst_id UUID;
  v_result record;
  v_allocated_wallet_id UUID;
  v_debt_id UUID;
  v_real_balance NUMERIC(14,2);
  v_allocated_balance NUMERIC(14,2);
  v_debt_remaining NUMERIC(14,2);
  v_debts_count INT;
  v_debt_status public.debt_status;
  v_paid_txn_id UUID;
  v_paid_at TIMESTAMPTZ;
  v_payout_debt_id UUID;
BEGIN
  -- Setup
  INSERT INTO auth.users (id, email) VALUES (v_user_id, 'test_' || v_user_id || '@mezan.test');
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);

  SELECT family_id, member_id
  INTO v_family_id, v_member_id
  FROM public.fn_create_initial_family('Test Family', 'Test Owner');

  SELECT id INTO v_real_wallet_id FROM public.wallets WHERE family_id = v_family_id AND type = 'REAL' LIMIT 1;
  PERFORM public.fn_record_opening_balance(v_family_id, v_real_wallet_id, 10000, now());

  -- Test 1: Exit Before Payout (Refund)
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 1', 1000, 'MONTHLY', 'MONTHLY', 10, 5, '2025-01-01'
  );
  
  SELECT id INTO v_inst_id FROM public.gameya_installments WHERE gameya_id = v_gameya_id ORDER BY due_date ASC LIMIT 1;
  PERFORM public.fn_record_gameya_installment_payment(v_family_id, v_inst_id, v_real_wallet_id);

  SELECT * INTO v_result FROM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_wallet_id, 'REFUND_TO_WALLET');
  
  IF v_result.net_amount != -1000 THEN
    RAISE EXCEPTION 'Test 1 Failed: Expected net_amount -1000, got %', v_result.net_amount;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM public.gameya_circles WHERE id = v_gameya_id AND status = 'CANCELLED') THEN
    RAISE EXCEPTION 'Test 1 Failed: Status not CANCELLED';
  END IF;
  
  -- Test 2: Exit Before Payout (Zero Paid)
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 2', 1000, 'MONTHLY', 'MONTHLY', 10, 5, '2025-01-01'
  );
  
  SELECT * INTO v_result FROM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_wallet_id, 'NOOP');
  
  IF v_result.net_amount != 0 THEN
    RAISE EXCEPTION 'Test 2 Failed: Expected net_amount 0, got %', v_result.net_amount;
  END IF;

  -- Test 3: Exit After Payout with payout_debt_id & PAY_NOW
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 3', 1000, 'MONTHLY', 'MONTHLY', 10, 5, '2025-01-01'
  );
  
  SELECT id INTO v_inst_id FROM public.gameya_installments WHERE gameya_id = v_gameya_id ORDER BY due_date ASC LIMIT 1;
  PERFORM public.fn_record_gameya_installment_payment(v_family_id, v_inst_id, v_real_wallet_id);
  
  SELECT debt_id INTO v_debt_id FROM public.fn_receive_flexible_gameya_payout(v_family_id, v_gameya_id, v_real_wallet_id);
  
  IF v_debt_id IS NULL THEN
    RAISE EXCEPTION 'Test 3 Setup Failed: No debt created';
  END IF;

  -- Exit PAY_NOW
  SELECT count(*) INTO v_debts_count FROM public.debts WHERE family_id = v_family_id;

  SELECT * INTO v_result FROM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_wallet_id, 'PAY_NOW');
  
  IF v_result.net_amount != 9000 THEN
    RAISE EXCEPTION 'Test 3 Failed: Expected net_amount 9000, got %', v_result.net_amount;
  END IF;

  IF v_result.debt_id != v_debt_id THEN
    RAISE EXCEPTION 'Test 3 Failed: Did not return existing debt_id';
  END IF;

  SELECT remaining_amount INTO v_debt_remaining FROM public.debts WHERE id = v_debt_id;
  IF v_debt_remaining != 0 THEN
    RAISE EXCEPTION 'Test 3 Failed: Debt remaining amount not 0, got %', v_debt_remaining;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.debts WHERE id = v_debt_id AND status = 'SETTLED') THEN
    RAISE EXCEPTION 'Test 3 Failed: Debt status is not SETTLED';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.debt_payments WHERE debt_id = v_debt_id AND family_id = v_family_id AND amount = 9000) THEN
    RAISE EXCEPTION 'Test 3 Failed: debt_payments row missing or incorrect';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.ledger_transactions WHERE id = v_result.settlement_transaction_id AND type = 'LOAN_PAYMENT_OUT') THEN
    RAISE EXCEPTION 'Test 3 Failed: Ledger transaction type is not LOAN_PAYMENT_OUT';
  END IF;

  IF (SELECT count(*) FROM public.debts WHERE family_id = v_family_id) > v_debts_count THEN
    RAISE EXCEPTION 'Test 3 Failed: Duplicate debt created';
  END IF;

  -- Test 4: Exit After Payout with payout_debt_id & CONVERT_TO_DEBT
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 4', 1000, 'MONTHLY', 'MONTHLY', 10, 5, '2025-01-01'
  );
  
  SELECT id INTO v_inst_id FROM public.gameya_installments WHERE gameya_id = v_gameya_id ORDER BY due_date ASC LIMIT 1;
  PERFORM public.fn_record_gameya_installment_payment(v_family_id, v_inst_id, v_real_wallet_id);
  
  SELECT debt_id INTO v_debt_id FROM public.fn_receive_flexible_gameya_payout(v_family_id, v_gameya_id, v_real_wallet_id);
  
  -- Exit CONVERT_TO_DEBT
  SELECT count(*) INTO v_debts_count FROM public.debts WHERE family_id = v_family_id;

  SELECT * INTO v_result FROM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_wallet_id, 'CONVERT_TO_DEBT');
  
  IF v_result.debt_id != v_debt_id THEN
    RAISE EXCEPTION 'Test 4 Failed: Created a duplicate debt instead of returning existing';
  END IF;

  IF (SELECT count(*) FROM public.debts WHERE family_id = v_family_id) > v_debts_count THEN
    RAISE EXCEPTION 'Test 4 Failed: Duplicate debt created in CONVERT_TO_DEBT';
  END IF;

  -- Test 5: Exit Zero Settlement (net_amount = 0)
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 5', 1000, 'MONTHLY', 'MONTHLY', 10, 10, '2025-01-01'
  );
  
  FOR v_inst_id IN SELECT id FROM public.gameya_installments WHERE gameya_id = v_gameya_id ORDER BY due_date ASC LOOP
    PERFORM public.fn_record_gameya_installment_payment(v_family_id, v_inst_id, v_real_wallet_id);
  END LOOP;
  
  PERFORM public.fn_receive_flexible_gameya_payout(v_family_id, v_gameya_id, v_real_wallet_id);
  
  BEGIN
    SELECT * INTO v_result FROM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_wallet_id, 'NOOP');
    RAISE EXCEPTION 'Test 5 Failed: Expected GAMEYA_ALREADY_COMPLETED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%GAMEYA_ALREADY_COMPLETED%' THEN RAISE EXCEPTION 'Test 5 Failed: Expected GAMEYA_ALREADY_COMPLETED, got %', SQLERRM; END IF;
  END;

  -- Test 6: Exit After Partial Debt Payment
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 6', 1000, 'MONTHLY', 'MONTHLY', 10, 5, '2025-01-01'
  );
  
  SELECT id INTO v_inst_id FROM public.gameya_installments WHERE gameya_id = v_gameya_id ORDER BY due_date ASC LIMIT 1;
  PERFORM public.fn_record_gameya_installment_payment(v_family_id, v_inst_id, v_real_wallet_id);
  
  SELECT transaction_id, paid_at INTO v_paid_txn_id, v_paid_at FROM public.gameya_installments WHERE id = v_inst_id;
  
  SELECT debt_id INTO v_debt_id FROM public.fn_receive_flexible_gameya_payout(v_family_id, v_gameya_id, v_real_wallet_id);
  
  -- The debt is 9000. Let's pay 4000.
  PERFORM public.fn_record_debt_payment(v_family_id, v_debt_id, 4000, v_real_wallet_id);
  
  SELECT * INTO v_result FROM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_wallet_id, 'PAY_NOW');
  
  IF v_result.net_amount != 5000 THEN
    RAISE EXCEPTION 'Test 6 Failed: Expected net_amount 5000, got %', v_result.net_amount;
  END IF;

  SELECT remaining_amount, status INTO v_debt_remaining, v_debt_status FROM public.debts WHERE id = v_debt_id;
  IF v_debt_remaining != 0 OR v_debt_status != 'SETTLED' THEN
    RAISE EXCEPTION 'Test 6 Failed: Debt not fully settled correctly';
  END IF;

  -- Test PAID installment immutability
  IF NOT EXISTS (
    SELECT 1 FROM public.gameya_installments 
    WHERE id = v_inst_id 
      AND status = 'PAID' 
      AND transaction_id = v_paid_txn_id 
      AND paid_at = v_paid_at
  ) THEN
    RAISE EXCEPTION 'Test 6 Failed: PAID installment was mutated during exit';
  END IF;

  -- Test 7: New debt linked back to gameya_circles
  -- Test creating a debt during exit (legacy gap).
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 7', 1000, 'MONTHLY', 'MONTHLY', 10, 5, '2025-01-01'
  );
  SELECT wallet_id INTO v_allocated_wallet_id FROM public.gameya_circles WHERE id = v_gameya_id;
  
  -- Force an exit state where payout > paid, but no payout_debt_id exists.
  UPDATE public.gameya_turns SET status = 'RECEIVED' WHERE gameya_id = v_gameya_id AND turn_number = 5;
  
  -- Add a fake payout link so v_payout_received = 9000
  INSERT INTO public.ledger_transactions (family_id, type, amount, from_wallet_id, to_wallet_id, description, created_by)
  VALUES (v_family_id, 'GAMEYA_PAYOUT', 9000, v_allocated_wallet_id, v_real_wallet_id, 'Mock Payout', v_member_id) RETURNING id INTO v_paid_txn_id;
  
  UPDATE public.gameya_circles SET payout_transaction_id = v_paid_txn_id WHERE id = v_gameya_id;
  
  SELECT * INTO v_result FROM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_wallet_id, 'CONVERT_TO_DEBT');
  
  SELECT payout_debt_id INTO v_payout_debt_id FROM public.gameya_circles WHERE id = v_gameya_id;
  IF v_payout_debt_id IS NULL OR v_payout_debt_id != v_result.debt_id THEN
    RAISE EXCEPTION 'Test 7 Failed: payout_debt_id was not updated in gameya_circles %', v_payout_debt_id;
  END IF;

  RAISE NOTICE 'test_flexible_gameya_exit_positive PASSED';
END $$;

ROLLBACK;
