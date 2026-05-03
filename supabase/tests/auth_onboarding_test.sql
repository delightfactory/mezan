-- =============================================================================
-- Mezan: auth_onboarding_test.sql
-- Verification tests for Auth Onboarding RPC and RLS policies.
-- Usage: Execute this file manually via psql or Supabase SQL Editor.
-- =============================================================================

BEGIN; -- Start transaction for tests, we will rollback at the end

DO $$
DECLARE
  v_user_id UUID := gen_random_uuid();
  v_family_id UUID;
  v_member_id UUID;
  v_count INTEGER;
  v_fake_family_id UUID := gen_random_uuid();
BEGIN
  RAISE NOTICE '--- Starting Mezan Auth & Onboarding Tests ---';

  -- 1. Create a dummy user in auth.users
  INSERT INTO auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) 
  VALUES (v_user_id, 'authenticated', 'authenticated', 'test_onboarding_' || gen_random_uuid() || '@example.com', 'password', now(), now());

  -- ---------------------------------------------------------------------------
  -- Test 1: Unauthenticated call fails and anon role is blocked
  -- ---------------------------------------------------------------------------
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.fn_create_initial_family('عائلة تجريبية');
    RAISE EXCEPTION 'TEST_FAILED: anon role call should have failed with permission denied.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLSTATE = '42501' THEN
        RAISE NOTICE 'Test 1a Passed: anon role blocked by GRANT/REVOKE.';
      ELSE
        RAISE EXCEPTION 'Unexpected error in Test 1a: %', SQLERRM;
      END IF;
  END;
  RESET ROLE;

  BEGIN
    PERFORM set_config('request.jwt.claims', '{}', true);
    PERFORM public.fn_create_initial_family('عائلة تجريبية');
    RAISE EXCEPTION 'TEST_FAILED: Unauthenticated call should have failed.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%UNAUTHENTICATED%' THEN
        RAISE NOTICE 'Test 1b Passed: Unauthenticated call blocked.';
      ELSE
        RAISE EXCEPTION 'Unexpected error in Test 1b: %', SQLERRM;
      END IF;
  END;

  -- ---------------------------------------------------------------------------
  -- Test 2: Authenticated user creates initial family successfully
  -- ---------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', v_user_id), true);
  
  SELECT family_id, member_id 
  INTO v_family_id, v_member_id 
  FROM public.fn_create_initial_family('عائلة تجريبية');

  IF v_family_id IS NULL OR v_member_id IS NULL THEN
    RAISE EXCEPTION 'TEST_FAILED: fn_create_initial_family returned NULL.';
  END IF;

  -- Verify user became OWNER
  SELECT count(*) INTO v_count FROM public.family_members 
  WHERE id = v_member_id AND role = 'OWNER' AND status = 'ACTIVE';
  IF v_count != 1 THEN
    RAISE EXCEPTION 'TEST_FAILED: User did not become OWNER.';
  END IF;

  -- Verify default wallets are created
  SELECT count(*) INTO v_count FROM public.wallets WHERE family_id = v_family_id;
  IF v_count != 3 THEN
    RAISE EXCEPTION 'TEST_FAILED: Default wallets were not created correctly. Found %', v_count;
  END IF;

  RAISE NOTICE 'Test 2 Passed: Initial family and wallets created successfully.';

  -- ---------------------------------------------------------------------------
  -- Test 3: RLS allows owner to select family after onboarding
  -- ---------------------------------------------------------------------------
  -- We drop to authenticated role to test actual RLS
  SET LOCAL ROLE authenticated;
  
  SELECT count(*) INTO v_count FROM public.family_groups WHERE id = v_family_id;
  IF v_count != 1 THEN
    RAISE EXCEPTION 'TEST_FAILED: RLS blocked OWNER from selecting their family.';
  END IF;
  
  RESET ROLE; -- Back to postgres
  RAISE NOTICE 'Test 3 Passed: RLS allows owner to select family.';

  -- ---------------------------------------------------------------------------
  -- Test 4: Second onboarding call fails safely
  -- ---------------------------------------------------------------------------
  BEGIN
    PERFORM public.fn_create_initial_family('عائلة أخرى');
    RAISE EXCEPTION 'TEST_FAILED: Second onboarding call should have failed.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%ALREADY_HAS_ACTIVE_FAMILY%' THEN
        RAISE NOTICE 'Test 4 Passed: Second onboarding call blocked safely.';
      ELSE
        RAISE EXCEPTION 'Unexpected error in Test 4: %', SQLERRM;
      END IF;
  END;

  -- ---------------------------------------------------------------------------
  -- Test 5: Direct insert into family_groups is blocked
  -- ---------------------------------------------------------------------------
  BEGIN
    SET LOCAL ROLE authenticated;
    INSERT INTO public.family_groups (name) VALUES ('محاولة اختراق');
    RAISE EXCEPTION 'TEST_FAILED: Direct insert into family_groups should be blocked.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLSTATE = '42501' THEN 
        RAISE NOTICE 'Test 5 Passed: Direct insert into family_groups blocked by RLS.';
      ELSE
        RAISE EXCEPTION 'Unexpected error in Test 5: %', SQLERRM;
      END IF;
  END;
  RESET ROLE;

  -- ---------------------------------------------------------------------------
  -- Test 6: Direct first-member insert bypass is blocked
  -- ---------------------------------------------------------------------------
  -- We will create a fake family as postgres, then try to join it directly as authenticated
  BEGIN
    INSERT INTO public.family_groups (id, name) VALUES (v_fake_family_id, 'عائلة وهمية');
    
    SET LOCAL ROLE authenticated;
    INSERT INTO public.family_members (family_id, user_id, role) 
    VALUES (v_fake_family_id, v_user_id, 'OWNER');
    
    RAISE EXCEPTION 'TEST_FAILED: Direct member insert bypass should be blocked.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLSTATE = '42501' THEN 
        RAISE NOTICE 'Test 6 Passed: Direct first-member insert blocked by RLS.';
      ELSE
        RAISE EXCEPTION 'Unexpected error in Test 6: %', SQLERRM;
      END IF;
  END;
  RESET ROLE;

  RAISE NOTICE '--- All Auth & Onboarding Tests Passed ---';

END $$;

ROLLBACK; -- Undo all test data insertions
