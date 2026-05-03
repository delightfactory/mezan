-- =============================================================================
-- Mezan: test_flexible_gameya_rpcs_negative.sql
-- Phase 7C: Negative Tests for Flexible Gameya Atomic RPCs
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_user_id UUID;
  v_family_id UUID;
  v_member_id UUID;
  v_real_wallet_id UUID;
  v_low_wallet_id UUID;
  v_alloc_wallet_id UUID;
  v_gameya_id UUID;
  v_gameya_sched_id UUID;
  v_inst_id UUID;
  v_inst2_id UUID;
  v_amount NUMERIC;
  v_status TEXT;
BEGIN
  -- Setup
  v_user_id := gen_random_uuid();
  INSERT INTO auth.users (id, email) VALUES (v_user_id, 'testgameyarpcneg@mezan.com');
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);

  SELECT family_id, member_id INTO v_family_id, v_member_id
  FROM public.fn_create_initial_family('Test RPC Neg Family', 'Test Owner');

  SELECT id INTO v_real_wallet_id FROM public.wallets WHERE family_id = v_family_id AND type = 'REAL' LIMIT 1;
  PERFORM public.fn_record_opening_balance(v_family_id, v_real_wallet_id, 10000, now());

  -- Create a low balance wallet for insufficient funds test
  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (v_family_id, 'Low Wallet', 'REAL', 0, v_member_id) RETURNING id INTO v_low_wallet_id;
  PERFORM public.fn_record_opening_balance(v_family_id, v_low_wallet_id, 10, now());

  -- 1. Create huge schedule over safe limit (e.g. 200 months weekly)
  BEGIN
    PERFORM public.fn_create_flexible_gameya_circle(
      v_family_id, 'Huge', 10, 'DAILY'::public.gameya_payment_frequency, 'MONTHLY'::public.gameya_turn_frequency,
      100, 1, CURRENT_DATE
    );
    RAISE EXCEPTION 'Negative Test Failed: Huge schedule allowed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%GAMEYA_INVALID_CONFIG%' THEN RAISE EXCEPTION 'Wrong error: %', SQLERRM; END IF;
  END;

  -- Create normal gameya
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Normal', 500, 'MONTHLY'::public.gameya_payment_frequency, 'MONTHLY'::public.gameya_turn_frequency,
    3, 2, CURRENT_DATE
  );

  SELECT id INTO v_inst_id FROM public.gameya_installments WHERE gameya_id = v_gameya_id AND installment_number = 1;

  -- 2. Insufficient balance payment
  BEGIN
    PERFORM public.fn_record_gameya_installment_payment(v_family_id, v_inst_id, v_low_wallet_id);
    RAISE EXCEPTION 'Negative Test Failed: allowed insufficient balance payment';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%INSUFFICIENT_BALANCE%' THEN RAISE EXCEPTION 'Wrong error: %', SQLERRM; END IF;
  END;

  -- 3. Pay twice
  PERFORM public.fn_record_gameya_installment_payment(v_family_id, v_inst_id, v_real_wallet_id);
  BEGIN
    PERFORM public.fn_record_gameya_installment_payment(v_family_id, v_inst_id, v_real_wallet_id);
    RAISE EXCEPTION 'Negative Test Failed: allowed double payment';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%GAMEYA_INSTALLMENT_ALREADY_PAID%' THEN RAISE EXCEPTION 'Wrong error: %', SQLERRM; END IF;
  END;

  -- 4. Payout turn out of bounds
  BEGIN
    PERFORM public.fn_change_gameya_payout_turn(v_family_id, v_gameya_id, 10);
    RAISE EXCEPTION 'Negative Test Failed: allowed out of bounds payout turn';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%GAMEYA_INVALID_PAYOUT_TURN%' THEN RAISE EXCEPTION 'Wrong error: %', SQLERRM; END IF;
  END;

  -- 5. Receive Payout twice
  PERFORM public.fn_receive_flexible_gameya_payout(v_family_id, v_gameya_id, v_real_wallet_id);
  BEGIN
    PERFORM public.fn_receive_flexible_gameya_payout(v_family_id, v_gameya_id, v_real_wallet_id);
    RAISE EXCEPTION 'Negative Test Failed: allowed payout twice';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%GAMEYA_PAYOUT_ALREADY_RECEIVED%' THEN RAISE EXCEPTION 'Wrong error: %', SQLERRM; END IF;
  END;

  -- 6. Change payout turn after payout
  BEGIN
    PERFORM public.fn_change_gameya_payout_turn(v_family_id, v_gameya_id, 3);
    RAISE EXCEPTION 'Negative Test Failed: allowed change payout turn after payout';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%GAMEYA_SCHEDULE_LOCKED%' THEN RAISE EXCEPTION 'Wrong error: %', SQLERRM; END IF;
  END;

  -- 7. Overfunded payout
  -- Create new gameya
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Overfunded', 100, 'MONTHLY'::public.gameya_payment_frequency, 'MONTHLY'::public.gameya_turn_frequency,
    3, 2, CURRENT_DATE
  );
  SELECT wallet_id INTO v_alloc_wallet_id FROM public.gameya_circles WHERE id = v_gameya_id;
  PERFORM public.fn_record_opening_balance(v_family_id, v_alloc_wallet_id, 5000, now());
  
  BEGIN
    PERFORM public.fn_receive_flexible_gameya_payout(v_family_id, v_gameya_id, v_real_wallet_id);
    RAISE EXCEPTION 'Negative Test Failed: allowed overfunded payout';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%GAMEYA_RESERVE_OVERFUNDED%' THEN RAISE EXCEPTION 'Wrong error: %', SQLERRM; END IF;
  END;

  -- 8. Schedule Update Check
  v_gameya_sched_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Sched', 100, 'MONTHLY'::public.gameya_payment_frequency, 'MONTHLY'::public.gameya_turn_frequency,
    3, 2, CURRENT_DATE
  );

  SELECT id INTO v_inst_id FROM public.gameya_installments WHERE gameya_id = v_gameya_sched_id AND installment_number = 1;
  PERFORM public.fn_record_gameya_installment_payment(v_family_id, v_inst_id, v_real_wallet_id);

  SELECT id INTO v_inst2_id FROM public.gameya_installments WHERE gameya_id = v_gameya_sched_id AND installment_number = 2;
  UPDATE public.gameya_installments SET status = 'OVERDUE' WHERE id = v_inst2_id;

  -- 9. Huge schedule update (Safe-Limit Negative Test)
  DECLARE
    v_huge_gameya_id UUID;
  BEGIN
    v_huge_gameya_id := public.fn_create_flexible_gameya_circle(
      v_family_id, 'Huge', 100, 'MONTHLY'::public.gameya_payment_frequency, 'MONTHLY'::public.gameya_turn_frequency,
      100, 2, CURRENT_DATE
    );
    PERFORM public.fn_update_gameya_future_schedule(
      v_family_id, v_huge_gameya_id, 200, 'DAILY'::public.gameya_payment_frequency
    );
    RAISE EXCEPTION 'Negative Test Failed: Huge schedule update allowed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%GAMEYA_INVALID_CONFIG%' THEN RAISE EXCEPTION 'Wrong error: %', SQLERRM; END IF;
  END;

  PERFORM public.fn_update_gameya_future_schedule(
    v_family_id, v_gameya_sched_id, 200, 'WEEKLY'::public.gameya_payment_frequency
  );

  SELECT amount, status INTO v_amount, v_status FROM public.gameya_installments WHERE id = v_inst_id;
  IF v_amount != 100 OR v_status != 'PAID' THEN
    RAISE EXCEPTION 'Negative Test Failed: PAID installment was modified by schedule update';
  END IF;

  SELECT amount, status INTO v_amount, v_status FROM public.gameya_installments WHERE id = v_inst2_id;
  IF v_amount != 100 OR v_status != 'OVERDUE' THEN
    RAISE EXCEPTION 'Negative Test Failed: OVERDUE installment was modified by schedule update';
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);

  RAISE NOTICE 'test_flexible_gameya_rpcs_negative PASSED';
END $$;

ROLLBACK;
