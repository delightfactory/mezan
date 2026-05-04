BEGIN;

SELECT plan(1);

-- 1. Setup Test User and Family
WITH new_user AS (
  INSERT INTO auth.users (id, email)
  VALUES (gen_random_uuid(), 'test_gameya_hardening@example.com')
  RETURNING id
),
new_family AS (
  INSERT INTO public.family_groups (id, name)
  SELECT gen_random_uuid(), 'Test Family' FROM new_user
  RETURNING id
),
new_member AS (
  INSERT INTO public.family_members (family_id, user_id, role)
  SELECT new_family.id, new_user.id, 'OWNER' FROM new_family, new_user
  RETURNING family_id, user_id
)
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}', user_id), true)
FROM new_member;

DO $$
DECLARE
  v_family_id uuid;
  v_alloc_w uuid;
  v_real_w uuid;
  v_gameya_id uuid;
  v_alloc_balance numeric;
  v_real_balance numeric;
  v_cancelled_count int;
  v_paid_count int;
  v_status text;
  v_debt_id uuid;
  v_opening_txn_count int;
  v_debt_balance numeric;
  v_debt_due_date date;
  v_safe_to_spend numeric;
BEGIN
  SELECT family_id INTO v_family_id FROM public.family_members LIMIT 1;
  
  -- Create Wallets
  INSERT INTO public.wallets (family_id, name, type, balance) 
  VALUES (v_family_id, 'Real Wallet', 'REAL', 10000) 
  RETURNING id INTO v_real_w;
  
  -- Test Case 1: Import with NO payout received
  -- Paid 2 installments, remaining 0
  v_gameya_id := public.fn_import_existing_gameya_circle(
    v_family_id, 'No Payout Gameya'::text, 1000::numeric, 'MONTHLY'::public.gameya_payment_frequency, 'MONTHLY'::public.gameya_turn_frequency,
    10::int, 5::int, (CURRENT_DATE - INTERVAL '2 months')::date, CURRENT_DATE::date,
    2::int, false, 0::numeric, 0::numeric
  );

  SELECT balance INTO v_alloc_balance FROM public.wallets WHERE family_id = v_family_id AND type = 'ALLOCATED';
  SELECT count(*) INTO v_opening_txn_count FROM public.ledger_transactions WHERE type = 'OPENING_BALANCE' AND to_wallet_id = (SELECT id FROM public.wallets WHERE family_id = v_family_id AND type = 'ALLOCATED');
  
  -- Test 1 & 2: Allocated balance funded by opening balance (2 * 1000)
  IF v_alloc_balance != 2000 THEN
    RAISE EXCEPTION 'Test failed: Expected allocated balance 2000, got %', v_alloc_balance;
  END IF;
  IF v_opening_txn_count != 1 THEN
    RAISE EXCEPTION 'Test failed: Expected 1 opening transaction, got %', v_opening_txn_count;
  END IF;

  -- Test Case 2: Import with Payout Received
  -- Paid 3 installments out of 10, payout turn 2. Remaining amount is 7000.
  v_gameya_id := public.fn_import_existing_gameya_circle(
    v_family_id, 'Payout Gameya'::text, 1000::numeric, 'MONTHLY'::public.gameya_payment_frequency, 'MONTHLY'::public.gameya_turn_frequency,
    10::int, 2::int, (CURRENT_DATE - INTERVAL '3 months')::date, CURRENT_DATE::date,
    3::int, true, 0::numeric, 7000::numeric
  );

  SELECT balance INTO v_alloc_balance FROM public.wallets WHERE family_id = v_family_id AND type = 'ALLOCATED';
  SELECT count(*) INTO v_opening_txn_count FROM public.ledger_transactions WHERE type = 'OPENING_BALANCE' AND to_wallet_id = (SELECT id FROM public.wallets WHERE family_id = v_family_id AND type = 'ALLOCATED');
  
  -- Test 3 & 4: Allocated balance should NOT have increased (remains 2000 from the first test)
  IF v_alloc_balance != 2000 THEN
    RAISE EXCEPTION 'Test failed: Expected allocated balance to remain 2000, got %', v_alloc_balance;
  END IF;
  IF v_opening_txn_count != 1 THEN
    RAISE EXCEPTION 'Test failed: Expected opening transaction count to remain 1, got %', v_opening_txn_count;
  END IF;

  -- Test 5: Gameya Status should be RECEIVED_PAYING_DEBT
  SELECT status, payout_debt_id INTO v_status, v_debt_id FROM public.gameya_circles WHERE id = v_gameya_id;
  IF v_status != 'RECEIVED_PAYING_DEBT' THEN
    RAISE EXCEPTION 'Test failed: Expected status RECEIVED_PAYING_DEBT, got %', v_status;
  END IF;

  -- Test 6 & 7: Debt was created correctly
  IF v_debt_id IS NULL THEN
    RAISE EXCEPTION 'Test failed: payout_debt_id is null';
  END IF;
  SELECT remaining_amount INTO v_debt_balance FROM public.debts WHERE id = v_debt_id;
  IF v_debt_balance != 7000 THEN
    RAISE EXCEPTION 'Test failed: Expected debt remaining amount 7000, got %', v_debt_balance;
  END IF;

  -- Test 8: Unpaid installments are CANCELLED
  SELECT count(*) INTO v_cancelled_count FROM public.gameya_installments WHERE gameya_id = v_gameya_id AND status = 'CANCELLED';
  IF v_cancelled_count != 7 THEN
    RAISE EXCEPTION 'Test failed: Expected 7 cancelled installments, got %', v_cancelled_count;
  END IF;

  -- Test Case 3: Exit from Imported Payout Gameya
  -- Pay the debt via PAY_NOW
  PERFORM public.fn_exit_flexible_gameya_circle(v_family_id, v_gameya_id, v_real_w, 'PAY_NOW', CURRENT_TIMESTAMP);
  
  SELECT status INTO v_status FROM public.gameya_circles WHERE id = v_gameya_id;
  IF v_status != 'CANCELLED' THEN
    RAISE EXCEPTION 'Test failed: Expected gameya status to be CANCELLED after exit, got %', v_status;
  END IF;
  
  SELECT remaining_amount INTO v_debt_balance FROM public.debts WHERE id = v_debt_id;
  IF v_debt_balance != 0 THEN
    RAISE EXCEPTION 'Test failed: Expected debt balance to be 0 after exit, got %', v_debt_balance;
  END IF;

  SELECT balance INTO v_real_balance FROM public.wallets WHERE id = v_real_w;
  IF v_real_balance != 3000 THEN -- 10000 - 7000 debt payment
    RAISE EXCEPTION 'Test failed: Expected real balance 3000, got %', v_real_balance;
  END IF;

  -- Test Case 4: Invalid Config - Paid installments > Total possible
  BEGIN
    PERFORM public.fn_import_existing_gameya_circle(
      v_family_id, 'Invalid Gameya'::text, 1000::numeric, 'MONTHLY'::public.gameya_payment_frequency, 'MONTHLY'::public.gameya_turn_frequency,
      10::int, 5::int, CURRENT_DATE::date, CURRENT_DATE::date,
      15::int, false, 0::numeric, 0::numeric
    );
    RAISE EXCEPTION 'Test failed: Expected GAMEYA_INVALID_CONFIG';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM != 'GAMEYA_INVALID_CONFIG' THEN
        RAISE EXCEPTION 'Test failed: Expected GAMEYA_INVALID_CONFIG, got %', SQLERRM;
      END IF;
  END;

  -- Test Case 5: Imported gameya with payout, but remaining is 0
  v_gameya_id := public.fn_import_existing_gameya_circle(
    v_family_id, 'Completed Payout Gameya'::text, 1000::numeric, 'MONTHLY'::public.gameya_payment_frequency, 'MONTHLY'::public.gameya_turn_frequency,
    10::int, 2::int, (CURRENT_DATE - INTERVAL '10 months')::date, CURRENT_DATE::date,
    10::int, true, 0::numeric, 0::numeric
  );

  SELECT status, payout_debt_id INTO v_status, v_debt_id FROM public.gameya_circles WHERE id = v_gameya_id;
  IF v_status != 'COMPLETED' THEN
    RAISE EXCEPTION 'Test failed: Expected status COMPLETED, got %', v_status;
  END IF;
  IF v_debt_id IS NOT NULL THEN
    RAISE EXCEPTION 'Test failed: Expected no debt for completed gameya, but got debt_id %', v_debt_id;
  END IF;

  -- Test Case 6: Safe To Spend Calculation Double Count check
  -- Debt is currently 0 active.
  -- Create an early payout situation
  v_gameya_id := public.fn_import_existing_gameya_circle(
    v_family_id, 'Early Payout Test Gameya'::text, 1000::numeric, 'MONTHLY'::public.gameya_payment_frequency, 'MONTHLY'::public.gameya_turn_frequency,
    10::int, 2::int, (CURRENT_DATE - INTERVAL '3 months')::date, CURRENT_DATE::date,
    3::int, true, 0::numeric, 7000::numeric
  );
  
  v_safe_to_spend := public.fn_calculate_safe_to_spend(v_family_id);
  -- Real Wallet = 3000. Debt = 7000. Gameya = 0 (cancelled). Safe to spend should be 0.
  IF v_safe_to_spend != 0 THEN
    RAISE EXCEPTION 'Test failed: Expected safe to spend 0, got %', v_safe_to_spend;
  END IF;

END $$;

SELECT pass('All Gameya Import Hardening constraints successfully validated.');

SELECT * FROM finish();
ROLLBACK;
