# Auth And Onboarding Review

**Date:** 2026-05-01  
**Decision:** Onboarding migration accepted by static review; onboarding test script needs syntax fixes before final verification.

## Accepted

- `fn_create_initial_family` exists as a `SECURITY DEFINER` RPC.
- It checks `auth.uid()`.
- It prevents onboarding if the user already has any active family membership.
- It creates:
  - `family_groups`
  - `family_members` as `OWNER`
  - default wallets: `كاش`, `بنك`, `طوارئ`
  - audit event
- Direct client insert policy for `family_groups` has been removed from `00014`.
- The first-member bypass in `family_members_insert` has been removed.

## Required Test Fix

`supabase/tests/auth_onboarding_test.sql` contains an invalid nested `DECLARE` in the middle of the main `DO` block.

Current problematic shape:

```sql
-- inside an existing DO block
DECLARE
  v_fake_family_id UUID := gen_random_uuid();
BEGIN
  ...
END;
```

Fix by either:

- declaring `v_fake_family_id UUID := gen_random_uuid();` in the top-level `DECLARE` section, or
- wrapping the nested block correctly:

```sql
BEGIN
  DECLARE
    v_fake_family_id UUID := gen_random_uuid();
  BEGIN
    ...
  END;
END;
```

Prefer the first option for clarity.

## Recommended Hardening

Because the project has not been applied to Supabase yet, editing `00014_rls_policies.sql` is acceptable. If these migrations are ever applied incrementally to an existing database, add explicit policy cleanup in `00019`, such as:

```sql
DROP POLICY IF EXISTS family_groups_insert ON public.family_groups;
DROP POLICY IF EXISTS family_members_insert ON public.family_members;
```

then recreate the final intended `family_members_insert` policy.

## Gate Status

- Migration: accepted by static review.
- Test script: not accepted until syntax is fixed.
- No Supabase apply yet.
- No Phase 3 until onboarding test script is corrected.

