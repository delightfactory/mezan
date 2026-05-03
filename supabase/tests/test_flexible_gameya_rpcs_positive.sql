-- =============================================================================
-- Mezan: test_flexible_gameya_rpcs_positive.sql
-- Phase 7C: Positive Tests for Flexible Gameya Atomic RPCs
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_user_id UUID;
  v_family_id UUID;
  v_member_id UUID;
  v_real_wallet_id UUID;
  v_alloc_wallet_id UUID;
  v_gameya_id UUID;
  v_gameya2_id UUID;
  v_inst_id UUID;
  v_turn_id UUID;
  v_txn_id UUID;
  v_debt_id UUID;
  v_count INT;
  v_amount NUMERIC;
  v_circle RECORD;
  v_real_initial NUMERIC;
  v_real_after NUMERIC;
  v_debt_record RECORD;
BEGIN
  -- Setup
  v_user_id := gen_random_uuid();
  INSERT INTO auth.users (id, email) VALUES (v_user_id, 'testgameyarpcpos@mezan.com');
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);

  SELECT family_id, member_id INTO v_family_id, v_member_id
  FROM public.fn_create_initial_family('Test RPC Pos Family', 'Test Owner');

  SELECT id INTO v_real_wallet_id FROM public.wallets WHERE family_id = v_family_id AND type = 'REAL' LIMIT 1;
  
  PERFORM public.fn_record_opening_balance(v_family_id, v_real_wallet_id, 10000, now());

  -- 1. Create flexible gameya
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    p_family_id := v_family_id,
    p_name := 'Test Weekly Flex',
    p_installment_amount := 100,
    p_payment_frequency := 'WEEKLY'::public.gameya_payment_frequency,
    p_turn_frequency := 'MONTHLY'::public.gameya_turn_frequency,
    p_total_turns := 10,
    p_payout_turn := 5,
    p_start_date := CURRENT_DATE
  );

  SELECT * INTO v_circle FROM public.gameya_circles WHERE id = v_gameya_id;
  SELECT COUNT(*) INTO v_count FROM public.gameya_installments WHERE gameya_id = v_gameya_id;
  
  IF v_circle.flex_payout_amount != (v_count * 100) THEN
    RAISE EXCEPTION 'Positive Test Failed: flex_payout_amount % does not match count % * 100', v_circle.flex_payout_amount, v_count;
  END IF;

  v_alloc_wallet_id := v_circle.wallet_id;

  -- 2. Record installment payment
  SELECT id INTO v_inst_id FROM public.gameya_installments WHERE gameya_id = v_gameya_id AND installment_number = 1;
  SELECT balance INTO v_real_initial FROM public.wallets WHERE id = v_real_wallet_id;
  
  v_txn_id := public.fn_record_gameya_installment_payment(
    p_family_id := v_family_id,
    p_installment_id := v_inst_id,
    p_real_wallet_id := v_real_wallet_id
  );

  -- Assertions for payment
  SELECT balance INTO v_real_after FROM public.wallets WHERE id = v_real_wallet_id;
  IF v_real_after != (v_real_initial - 100) THEN
    RAISE EXCEPTION 'REAL wallet balance did not decrease correctly';
  END IF;

  SELECT balance INTO v_amount FROM public.wallets WHERE id = v_alloc_wallet_id;
  IF v_amount != 100 THEN RAISE EXCEPTION 'Allocated wallet balance is not 100'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.ledger_transactions WHERE id = v_txn_id AND type = 'GAMEYA_INSTALLMENT') THEN
    RAISE EXCEPTION 'Ledger transaction GAMEYA_INSTALLMENT not found';
  END IF;

  IF EXISTS (SELECT 1 FROM public.gameya_turns WHERE gameya_id = v_gameya_id AND status != 'UPCOMING') THEN
    RAISE EXCEPTION 'Turns should not change status upon payment';
  END IF;

  -- 3. Change payout turn before payout
  PERFORM public.fn_change_gameya_payout_turn(v_family_id, v_gameya_id, 2);
  SELECT payout_turn INTO v_count FROM public.gameya_circles WHERE id = v_gameya_id;
  IF v_count != 2 THEN RAISE EXCEPTION 'Payout turn was not changed'; END IF;

  -- 4. Receive payout (Early payout -> creates debt)
  SELECT * FROM public.fn_receive_flexible_gameya_payout(v_family_id, v_gameya_id, v_real_wallet_id) INTO v_txn_id, v_debt_id;

  IF v_debt_id IS NULL THEN
    RAISE EXCEPTION 'Debt was not created for early payout';
  END IF;

  -- Assertions for Payout
  SELECT * INTO v_debt_record FROM public.debts WHERE id = v_debt_id;
  IF v_debt_record.direction != 'BORROWED_FROM' THEN
    RAISE EXCEPTION 'Debt direction is wrong';
  END IF;
  IF v_debt_record.original_amount != (v_circle.flex_payout_amount - 100) THEN
    RAISE EXCEPTION 'Debt amount is wrong';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.ledger_transactions WHERE type = 'GAMEYA_PAYOUT' AND from_wallet_id = v_alloc_wallet_id) THEN
    RAISE EXCEPTION 'Ledger transaction GAMEYA_PAYOUT not found';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.ledger_transactions WHERE type = 'LOAN_RECEIVE' AND to_wallet_id = v_real_wallet_id) THEN
    RAISE EXCEPTION 'Ledger transaction LOAN_RECEIVE not found';
  END IF;

  SELECT status, transaction_id, paid_at INTO v_circle FROM public.gameya_turns WHERE gameya_id = v_gameya_id AND turn_number = 2;
  IF v_circle.status != 'RECEIVED' THEN RAISE EXCEPTION 'Target turn was not marked RECEIVED'; END IF;
  IF v_circle.transaction_id IS NULL THEN RAISE EXCEPTION 'Target turn missing transaction_id'; END IF;
  IF v_circle.paid_at IS NULL THEN RAISE EXCEPTION 'Target turn missing paid_at'; END IF;

  SELECT balance INTO v_amount FROM public.wallets WHERE id = v_alloc_wallet_id;
  IF v_amount != 0 THEN RAISE EXCEPTION 'Allocated wallet is not empty after payout'; END IF;

  -- Verify no double obligation
  SELECT COUNT(*) INTO v_count FROM public.gameya_installments WHERE gameya_id = v_gameya_id AND status IN ('UPCOMING','OVERDUE');
  IF v_count != 0 THEN RAISE EXCEPTION 'Positive Test Failed: unpaid installments not cancelled after debt creation'; END IF;

  PERFORM set_config('request.jwt.claims', '', true);

  RAISE NOTICE 'test_flexible_gameya_rpcs_positive PASSED';
END $$;

ROLLBACK;
