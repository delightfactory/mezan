-- =============================================================================
-- Mezan: test_flexible_gameya_exit_negative.sql
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_user_id UUID := gen_random_uuid();
  v_other_user_id UUID := gen_random_uuid();
  v_family_id UUID;
  v_member_id UUID;
  v_real_wallet_id UUID;
  v_gameya_id UUID;
  v_inst_id UUID;
  v_other_family UUID;
  v_other_member_id UUID;
  v_zero_wallet_id UUID;
BEGIN
  -- Setup Main Family
  INSERT INTO auth.users (id, email) VALUES (v_user_id, 'test_' || v_user_id || '@mezan.test');
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);

  SELECT family_id, member_id
  INTO v_family_id, v_member_id
  FROM public.fn_create_initial_family('Test Family', 'Test Owner');

  SELECT id INTO v_real_wallet_id FROM public.wallets WHERE family_id = v_family_id AND type = 'REAL' LIMIT 1;
  PERFORM public.fn_record_opening_balance(v_family_id, v_real_wallet_id, 10000, now());

  -- Setup Other Family
  INSERT INTO auth.users (id, email) VALUES (v_other_user_id, 'other_' || v_other_user_id || '@mezan.test');
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_other_user_id)::text, true);

  SELECT family_id, member_id
  INTO v_other_family, v_other_member_id
  FROM public.fn_create_initial_family('Other Family', 'Other Owner');

  -- Switch back to main user for most tests
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);

  -- Test 1: Exit Twice
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 1', 1000, 'MONTHLY', 'MONTHLY', 10, 5, '2025-01-01'
  );
  PERFORM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_wallet_id, 'NOOP');
  
  BEGIN
    PERFORM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_wallet_id, 'NOOP');
    RAISE EXCEPTION 'Test 1 Failed: Allowed exiting twice';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM != 'GAMEYA_ALREADY_CANCELLED' THEN
      RAISE EXCEPTION 'Test 1 Failed: Expected GAMEYA_ALREADY_CANCELLED, got %', SQLERRM;
    END IF;
  END;

  -- Test 2: Invalid Mode Before Payout
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 2', 1000, 'MONTHLY', 'MONTHLY', 10, 5, '2025-01-01'
  );
  SELECT id INTO v_inst_id FROM public.gameya_installments WHERE gameya_id = v_gameya_id ORDER BY due_date ASC LIMIT 1;
  PERFORM public.fn_record_gameya_installment_payment(v_family_id, v_inst_id, v_real_wallet_id);
  
  BEGIN
    PERFORM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_wallet_id, 'PAY_NOW');
    RAISE EXCEPTION 'Test 2 Failed: Allowed PAY_NOW before payout';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM != 'GAMEYA_INVALID_SETTLEMENT_MODE' THEN
      RAISE EXCEPTION 'Test 2 Failed: Expected GAMEYA_INVALID_SETTLEMENT_MODE, got %', SQLERRM;
    END IF;
  END;

  -- Test 3: Invalid Mode After Payout
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 3', 1000, 'MONTHLY', 'MONTHLY', 10, 5, '2025-01-01'
  );
  SELECT id INTO v_inst_id FROM public.gameya_installments WHERE gameya_id = v_gameya_id ORDER BY due_date ASC LIMIT 1;
  PERFORM public.fn_record_gameya_installment_payment(v_family_id, v_inst_id, v_real_wallet_id);
  PERFORM public.fn_receive_flexible_gameya_payout(v_family_id, v_gameya_id, v_real_wallet_id);
  
  BEGIN
    PERFORM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_wallet_id, 'REFUND_TO_WALLET');
    RAISE EXCEPTION 'Test 3 Failed: Allowed REFUND_TO_WALLET when owing money';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM != 'GAMEYA_INVALID_SETTLEMENT_MODE' THEN
      RAISE EXCEPTION 'Test 3 Failed: Expected GAMEYA_INVALID_SETTLEMENT_MODE, got %', SQLERRM;
    END IF;
  END;

  -- Test 4: PAY_NOW Insufficient Balance
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 4', 1000, 'MONTHLY', 'MONTHLY', 10, 5, '2025-01-01'
  );
  SELECT id INTO v_inst_id FROM public.gameya_installments WHERE gameya_id = v_gameya_id ORDER BY due_date ASC LIMIT 1;
  PERFORM public.fn_record_gameya_installment_payment(v_family_id, v_inst_id, v_real_wallet_id);
  PERFORM public.fn_receive_flexible_gameya_payout(v_family_id, v_gameya_id, v_real_wallet_id);
  
  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (v_family_id, 'Zero Wallet', 'REAL', 0, v_member_id)
  RETURNING id INTO v_zero_wallet_id;
  
  BEGIN
    PERFORM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_zero_wallet_id, 'PAY_NOW');
    RAISE EXCEPTION 'Test 4 Failed: Allowed PAY_NOW with insufficient balance';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM != 'INSUFFICIENT_BALANCE' THEN
      RAISE EXCEPTION 'Test 4 Failed: Expected INSUFFICIENT_BALANCE, got %', SQLERRM;
    END IF;
  END;

  -- Test 5: Cross-Family Attempt
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 5', 1000, 'MONTHLY', 'MONTHLY', 10, 5, '2025-01-01'
  );
  
  -- Switch to other user context
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_other_user_id)::text, true);

  BEGIN
    PERFORM public.fn_exit_flexible_gameya_circle(v_other_family, v_gameya_id, v_real_wallet_id, 'NOOP');
    RAISE EXCEPTION 'Test 5 Failed: Allowed cross-family exit';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM != 'GAMEYA_NOT_FOUND' AND SQLERRM != 'ACCESS_DENIED' AND SQLERRM != 'MEMBER_NOT_FOUND' THEN
      RAISE EXCEPTION 'Test 5 Failed: Expected GAMEYA_NOT_FOUND/ACCESS_DENIED/MEMBER_NOT_FOUND, got %', SQLERRM;
    END IF;
  END;

  -- Restore user context for Test 6
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);

  -- Test 6: Missing payout links
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Gameya 6', 1000, 'MONTHLY', 'MONTHLY', 10, 5, '2025-01-01'
  );
  UPDATE public.gameya_turns SET status = 'RECEIVED' WHERE gameya_id = v_gameya_id AND turn_number = 5;
  
  BEGIN
    PERFORM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_wallet_id, 'PAY_NOW');
    RAISE EXCEPTION 'Test 6 Failed: Allowed exit with missing payout links';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM != 'GAMEYA_SETTLEMENT_REQUIRED' THEN
      RAISE EXCEPTION 'Test 6 Failed: Expected GAMEYA_SETTLEMENT_REQUIRED, got %', SQLERRM;
    END IF;
  END;

  RAISE NOTICE 'test_flexible_gameya_exit_negative PASSED';
END $$;

ROLLBACK;
