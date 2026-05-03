BEGIN;
DO $$
DECLARE
  v_user_id UUID := gen_random_uuid();
  v_family_id UUID;
  v_member_id UUID;
  v_count INTEGER;
BEGIN
  RAISE NOTICE '--- Starting Mezan Auth & Onboarding POSITIVE Test ---';

  INSERT INTO auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) 
  VALUES (v_user_id, 'authenticated', 'authenticated', 'test_onboarding_' || gen_random_uuid() || '@example.com', 'password', now(), now());

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', v_user_id), true);
  
  SELECT family_id, member_id 
  INTO v_family_id, v_member_id 
  FROM public.fn_create_initial_family('عائلة تجريبية');

  IF v_family_id IS NULL OR v_member_id IS NULL THEN
    RAISE EXCEPTION 'TEST_FAILED: fn_create_initial_family returned NULL.';
  END IF;

  SELECT count(*) INTO v_count FROM public.family_members 
  WHERE id = v_member_id AND role = 'OWNER' AND status = 'ACTIVE';
  IF v_count != 1 THEN
    RAISE EXCEPTION 'TEST_FAILED: User did not become OWNER.';
  END IF;

  SELECT count(*) INTO v_count FROM public.wallets WHERE family_id = v_family_id;
  IF v_count != 3 THEN
    RAISE EXCEPTION 'TEST_FAILED: Default wallets were not created correctly.';
  END IF;

  RAISE NOTICE 'Test Passed: Initial family and wallets created successfully.';
END $$;
ROLLBACK;
