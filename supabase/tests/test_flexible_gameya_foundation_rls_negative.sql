-- =============================================================================
-- Mezan: test_flexible_gameya_foundation_rls_negative.sql
-- Phase 7B: Flexible Gameya Foundation Backend Tests (Negative RLS)
-- Note: RLS tests are limited when run as postgres superuser, but we can test
-- the CHECK constraints and verify the structure of the RLS policies statically.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_user_id UUID;
  v_family_id UUID;
  v_member_id UUID;
  v_gameya_id UUID;
BEGIN
  -- Setup isolated test data
  v_user_id := gen_random_uuid();
  INSERT INTO auth.users (id, email) VALUES (v_user_id, 'testgameyaneg@mezan.com');
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);

  SELECT family_id, member_id 
  INTO v_family_id, v_member_id
  FROM public.fn_create_initial_family('Test Flex Neg Family', 'Test Owner');

  v_gameya_id := gen_random_uuid();
  INSERT INTO public.gameya_circles (
    id, family_id, name, status, start_date, monthly_installment, total_months, payout_month, created_by
  ) VALUES (
    v_gameya_id, v_family_id, 'Neg Gameya', 'SAVING_PHASE', CURRENT_DATE, 1000, 3, 2, v_member_id
  );

  -- 1. Negative Test: Amount <= 0
  BEGIN
    INSERT INTO public.gameya_installments (gameya_id, family_id, installment_number, due_date, amount, status)
    VALUES (v_gameya_id, v_family_id, 1, CURRENT_DATE, 0, 'UPCOMING');
    RAISE EXCEPTION 'Negative Test Failed: allowed amount <= 0';
  EXCEPTION WHEN check_violation THEN
    -- Expected
  END;

  -- 2. Verify RLS policies are structurally correct
  -- (Since we cannot reliably simulate client role without a full client test suite, 
  -- we verify the policies exist and restrict appropriately).
  
  -- Ensure only SELECT policy exists
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'gameya_installments' 
      AND cmd IN ('INSERT', 'UPDATE', 'DELETE')
  ) THEN
    RAISE EXCEPTION 'Negative Test Failed: INSERT/UPDATE/DELETE policies exist on gameya_installments';
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);

  RAISE NOTICE 'test_flexible_gameya_foundation_rls_negative PASSED';
END $$;

ROLLBACK;
