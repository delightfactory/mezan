-- =============================================================================
-- Mezan: suspended_member_guard.test.sql
-- =============================================================================
BEGIN;
SELECT plan(6);

-- 1. Setup Data
SELECT * FROM tests.create_supabase_user('owner_smg');
SELECT * FROM tests.create_supabase_user('suspended_smg');
SELECT * FROM tests.create_supabase_user('clean_smg');

-- Authenticate as owner and create family
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}', id), true) FROM auth.users WHERE email = 'owner_smg@test.com';

-- Save family id to a temp table
CREATE TEMP TABLE smg_state (
    family_id UUID,
    member_id UUID
);

INSERT INTO smg_state (family_id)
SELECT family_id FROM public.fn_create_initial_family('Guard Fam', 'Owner');

-- Add suspended_smg to family and suspend them
WITH new_mem AS (
  INSERT INTO public.family_members(family_id, user_id, role, status, display_name)
  SELECT (SELECT family_id FROM smg_state LIMIT 1), id, 'MEMBER', 'SUSPENDED', 'Suspended Member'
  FROM auth.users WHERE email = 'suspended_smg@test.com'
  RETURNING id
)
UPDATE smg_state SET member_id = (SELECT id FROM new_mem);

-- Test 1: Suspended user cannot create initial family
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}', id), true) FROM auth.users WHERE email = 'suspended_smg@test.com';
SELECT throws_ok(
  'SELECT public.fn_create_initial_family(''My New Fam'', ''Suspended User'')',
  'MEMBERSHIP_SUSPENDED',
  'Suspended user cannot create a family'
);

-- Test 2: Suspended user state returns SUSPENDED
SELECT results_eq(
  'SELECT status FROM public.fn_get_my_membership_state()',
  ARRAY['SUSPENDED'::TEXT],
  'fn_get_my_membership_state returns SUSPENDED for suspended user'
);

-- Test 3: Active user cannot create initial family
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}', id), true) FROM auth.users WHERE email = 'owner_smg@test.com';
SELECT throws_ok(
  'SELECT public.fn_create_initial_family(''Another Fam'', ''Owner'')',
  'ALREADY_HAS_ACTIVE_FAMILY',
  'Active user cannot create a family'
);

-- Test 4: Clean user can create initial family
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}', id), true) FROM auth.users WHERE email = 'clean_smg@test.com';
SELECT lives_ok(
  'SELECT public.fn_create_initial_family(''Clean Fam'', ''Clean'')',
  'Clean user can create a family'
);

-- Test 5: Reactivate a suspended member works if no other active family
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}', id), true) FROM auth.users WHERE email = 'owner_smg@test.com';
SELECT lives_ok(
  format('SELECT public.fn_reactivate_family_member(''%s'', ''%s'')', (SELECT family_id FROM smg_state LIMIT 1), (SELECT member_id FROM smg_state LIMIT 1)),
  'Reactivating a suspended member with no other active family succeeds'
);

-- Put them back in suspended state for the conflict test
UPDATE public.family_members 
SET status = 'SUSPENDED' 
WHERE id = (SELECT member_id FROM smg_state LIMIT 1);

-- Test 6: Reactivate fails with ONE_FAMILY_LIMIT if they have another active family
-- We insert an active family for the suspended user bypassing the RPC for test setup
INSERT INTO public.family_members(family_id, user_id, role, status, display_name)
SELECT (SELECT id FROM public.family_groups WHERE name = 'Clean Fam' LIMIT 1), id, 'MEMBER', 'ACTIVE', 'Conflicting Member'
FROM auth.users WHERE email = 'suspended_smg@test.com';

SELECT throws_ok(
  format('SELECT public.fn_reactivate_family_member(''%s'', ''%s'')', (SELECT family_id FROM smg_state LIMIT 1), (SELECT member_id FROM smg_state LIMIT 1)),
  'ONE_FAMILY_LIMIT: User already has an active family membership.',
  'fn_reactivate_family_member guards against duplicate active memberships'
);

SELECT * FROM finish();
ROLLBACK;
