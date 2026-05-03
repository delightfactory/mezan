-- =============================================================================
-- Mezan: test_flexible_gameya_foundation_positive.sql
-- Phase 7B: Flexible Gameya Foundation Backend Tests (Positive)
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_user_id UUID;
  v_family_id UUID;
  v_member_id UUID;
  v_wallet_id UUID;
  v_gameya_id UUID;
  v_count INT;
  v_safe NUMERIC;
  v_circle RECORD;
BEGIN
  -- 1. Setup isolated test data using onboarding RPC
  v_user_id := gen_random_uuid();
  INSERT INTO auth.users (id, email) VALUES (v_user_id, 'testgameyapos@mezan.com');
  
  -- Mock JWT
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);

  -- Call onboarding
  SELECT family_id, member_id 
  INTO v_family_id, v_member_id
  FROM public.fn_create_initial_family('Test Flex Family', 'Test Owner');

  -- Get the created REAL wallet
  SELECT id INTO v_wallet_id FROM public.wallets WHERE family_id = v_family_id AND type = 'REAL' LIMIT 1;
  
  -- Add balance via ledger
  PERFORM public.fn_record_opening_balance(
    v_family_id,
    v_wallet_id,
    10000,
    now()
  );

  -- 2. Create Legacy Gameya directly via DML (simulating before migration)
  v_gameya_id := gen_random_uuid();
  INSERT INTO public.gameya_circles (
    id, family_id, name, status, start_date, monthly_installment, total_months, payout_month, created_by
  ) VALUES (
    v_gameya_id, v_family_id, 'Legacy Gameya', 'SAVING_PHASE', CURRENT_DATE, 1000, 3, 2, v_member_id
  );

  -- Create 3 turns
  INSERT INTO public.gameya_turns (gameya_id, family_id, turn_number, due_date, status)
  VALUES 
    (v_gameya_id, v_family_id, 1, CURRENT_DATE, 'MISSED'),
    (v_gameya_id, v_family_id, 2, CURRENT_DATE + interval '1 month', 'UPCOMING'),
    (v_gameya_id, v_family_id, 3, CURRENT_DATE + interval '2 months', 'UPCOMING');

  -- 3. Run Backfill logic manually to simulate what migration did
  INSERT INTO public.gameya_installments (
    gameya_id, family_id, installment_number, due_date, amount, status
  )
  SELECT t.gameya_id, t.family_id, t.turn_number, t.due_date, c.monthly_installment,
    CASE 
      WHEN t.status = 'PAID' THEN 'PAID'::public.occurrence_status
      WHEN t.status = 'MISSED' THEN 'OVERDUE'::public.occurrence_status
      WHEN t.status = 'UPCOMING' THEN 'UPCOMING'::public.occurrence_status
      ELSE 'UPCOMING'::public.occurrence_status
    END
  FROM public.gameya_turns t JOIN public.gameya_circles c ON c.id = t.gameya_id
  WHERE t.gameya_id = v_gameya_id
  ON CONFLICT DO NOTHING;

  UPDATE public.gameya_circles c
  SET legacy_migrated_at = NOW(),
      installment_amount = monthly_installment,
      payment_frequency = 'MONTHLY'::public.gameya_payment_frequency,
      turn_frequency = 'MONTHLY'::public.gameya_turn_frequency,
      total_turns = total_months,
      payout_turn = payout_month,
      expected_payout_date = (start_date + make_interval(months => payout_month - 1))::date,
      flex_payout_amount = payout_amount
  WHERE EXISTS (SELECT 1 FROM public.gameya_installments i WHERE i.gameya_id = c.id) 
  AND c.id = v_gameya_id;

  -- Verify compatibility fields
  SELECT * INTO v_circle FROM public.gameya_circles WHERE id = v_gameya_id;
  IF v_circle.installment_amount != 1000 THEN RAISE EXCEPTION 'Installment amount mismatch'; END IF;
  IF v_circle.payment_frequency != 'MONTHLY' THEN RAISE EXCEPTION 'Payment frequency mismatch'; END IF;
  IF v_circle.turn_frequency != 'MONTHLY' THEN RAISE EXCEPTION 'Turn frequency mismatch'; END IF;
  IF v_circle.total_turns != 3 THEN RAISE EXCEPTION 'Total turns mismatch'; END IF;
  IF v_circle.payout_turn != 2 THEN RAISE EXCEPTION 'Payout turn mismatch'; END IF;
  IF v_circle.legacy_migrated_at IS NULL THEN RAISE EXCEPTION 'Legacy migrated at is null'; END IF;
  IF v_circle.expected_payout_date IS NULL THEN RAISE EXCEPTION 'Expected payout date is null'; END IF;
  IF v_circle.flex_payout_amount != 3000 THEN RAISE EXCEPTION 'Flex payout amount mismatch'; END IF;

  -- 4. Verify backfill generated 3 installments
  SELECT COUNT(*) INTO v_count FROM public.gameya_installments WHERE gameya_id = v_gameya_id;
  IF v_count != 3 THEN RAISE EXCEPTION 'Backfill failed: Expected 3 installments, got %', v_count; END IF;

  -- 5. Verify rerun doesn't double
  INSERT INTO public.gameya_installments (gameya_id, family_id, installment_number, due_date, amount, status)
  SELECT t.gameya_id, t.family_id, t.turn_number, t.due_date, 1000, 'UPCOMING'
  FROM public.gameya_turns t WHERE t.gameya_id = v_gameya_id
  ON CONFLICT DO NOTHING;
  
  SELECT COUNT(*) INTO v_count FROM public.gameya_installments WHERE gameya_id = v_gameya_id;
  IF v_count != 3 THEN RAISE EXCEPTION 'Rerun backfill failed: Expected 3 installments, got %', v_count; END IF;

  -- 6. Verify safe_to_spend uses installments and avoids double counting
  -- Turn 1 is CURRENT_DATE (this month) and OVERDUE. 
  -- Safe to spend should deduct only 1000 from 10000 = 9000.
  SELECT public.fn_calculate_safe_to_spend(v_family_id) INTO v_safe;
  IF v_safe != 9000 THEN RAISE EXCEPTION 'Safe to spend deduction failed: expected 9000, got %', v_safe; END IF;

  -- Mark installment 1 as PAID, safe_to_spend should be 10000
  UPDATE public.gameya_installments SET status = 'PAID' WHERE gameya_id = v_gameya_id AND installment_number = 1;
  SELECT public.fn_calculate_safe_to_spend(v_family_id) INTO v_safe;
  IF v_safe != 10000 THEN RAISE EXCEPTION 'Safe to spend PAID failed: expected 10000, got %', v_safe; END IF;

  -- Clear jwt config
  PERFORM set_config('request.jwt.claims', '', true);

  RAISE NOTICE 'test_flexible_gameya_foundation_positive PASSED';
END $$;

ROLLBACK;
