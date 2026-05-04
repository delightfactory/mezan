BEGIN;

SELECT plan(1);

-- 1. Setup Test User and Family
WITH new_user AS (
  INSERT INTO auth.users (id, email)
  VALUES (gen_random_uuid(), 'test_gameya_safe2spend@example.com')
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
  v_real_w uuid;
  v_alloc_w uuid;
  v_gameya_id uuid;
  v_safe_to_spend numeric;
BEGIN
  SELECT family_id INTO v_family_id FROM public.family_members LIMIT 1;
  
  -- Create Wallets (Real wallet has 10,000)
  INSERT INTO public.wallets (family_id, name, type, balance) 
  VALUES (v_family_id, 'Real Wallet', 'REAL', 10000) 
  RETURNING id INTO v_real_w;



  -- Verify initial safe to spend
  v_safe_to_spend := public.fn_calculate_safe_to_spend(v_family_id);
  IF v_safe_to_spend != 10000 THEN
    RAISE EXCEPTION 'Test 1 failed: Expected initial safe to spend 10000, got %', v_safe_to_spend;
  END IF;

  -- Create a standard gameya with 1000 monthly
  v_gameya_id := public.fn_create_flexible_gameya_circle(
    v_family_id, 'Test Standard Gameya', 1000, 'MONTHLY'::public.gameya_payment_frequency, 'MONTHLY'::public.gameya_turn_frequency,
    10, 5, CURRENT_DATE
  );

  -- Safe to spend should now be 9000 (1 upcoming installment in current month)
  v_safe_to_spend := public.fn_calculate_safe_to_spend(v_family_id);
  IF v_safe_to_spend != 9000 THEN
    RAISE EXCEPTION 'Test 2 failed: Expected safe to spend 9000, got %', v_safe_to_spend;
  END IF;

  -- Get the actual gameya allocated wallet
  SELECT wallet_id INTO v_alloc_w FROM public.gameya_circles WHERE id = v_gameya_id;

  -- Pay the installment
  -- Mock the payment for testing
  UPDATE public.gameya_installments SET status = 'PAID' WHERE gameya_id = v_gameya_id AND installment_number = 1;
  UPDATE public.wallets SET balance = balance - 1000 WHERE id = v_real_w;
  UPDATE public.wallets SET balance = balance + 1000 WHERE id = v_alloc_w;

  -- Safe to spend should now be 9000 (Wallet is 9000, no upcoming installment this month)
  v_safe_to_spend := public.fn_calculate_safe_to_spend(v_family_id);
  IF v_safe_to_spend != 9000 THEN
    RAISE EXCEPTION 'Test 3 failed: Expected safe to spend 9000 after payment, got %', v_safe_to_spend;
  END IF;

  -- Now let's trigger an early payout
  -- Real wallet goes to 19000. Debt = 9000. Remaining Unpaid Installments are CANCELLED.
  PERFORM public.fn_receive_flexible_gameya_payout(v_family_id, v_gameya_id, v_real_w, CURRENT_TIMESTAMP);

  -- Let's check the wallet balance
  IF (SELECT balance FROM public.wallets WHERE id = v_real_w) != 19000 THEN
    RAISE EXCEPTION 'Test 4 failed: Expected Real Wallet 19000 after payout, got %', (SELECT balance FROM public.wallets WHERE id = v_real_w);
  END IF;

  -- Let's check the active debt
  IF (SELECT sum(remaining_amount) FROM public.debts WHERE family_id = v_family_id AND status = 'ACTIVE') != 9000 THEN
    RAISE EXCEPTION 'Test 5 failed: Expected active debt of 9000, got %', (SELECT sum(remaining_amount) FROM public.debts WHERE family_id = v_family_id AND status = 'ACTIVE');
  END IF;

  -- The cancelled installments should NOT be counted in safe to spend
  v_safe_to_spend := public.fn_calculate_safe_to_spend(v_family_id);
  
  -- Real Wallet = 19000
  -- Debt = 9000
  -- Gameya = 0 (installments are CANCELLED or ignored because payout_debt_id is set)
  -- Expected safe to spend = 10000
  IF v_safe_to_spend != 10000 THEN
    RAISE EXCEPTION 'Test 6 failed: Expected safe to spend 10000, got %. Double counting detected!', v_safe_to_spend;
  END IF;

END $$;

SELECT pass('All Safe to Spend constraints successfully validated.');

SELECT * FROM finish();
ROLLBACK;
