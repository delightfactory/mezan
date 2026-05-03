BEGIN;
DO $$
DECLARE
  v_user_id UUID := gen_random_uuid();
  v_family_id UUID;
  v_member_id UUID;
BEGIN
  INSERT INTO auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) 
  VALUES (v_user_id, 'authenticated', 'authenticated', 'test_onboarding_' || gen_random_uuid() || '@example.com', 'password', now(), now());

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', v_user_id), true);
  
  SELECT family_id, member_id 
  INTO v_family_id, v_member_id 
  FROM public.fn_create_initial_family('عائلة تجريبية');

  RAISE NOTICE 'Created family: %', v_family_id;
END $$;
ROLLBACK;
