# Auth And Onboarding Final Review

**Date:** 2026-05-01  
**Decision:** Not approved for Phase 3 yet; one concurrency blocker remains.

## Accepted

- `auth_onboarding_test.sql` no longer has the invalid nested `DECLARE`.
- `00019_onboarding_rpc.sql` creates the initial family, owner membership, default wallets, and audit event atomically.
- `family_groups_insert` is removed.
- first-member direct insert bypass is removed.
- Incremental policy hardening was added to `00019`.

## Blocking Finding: Concurrent Onboarding Race

`fn_create_initial_family` prevents duplicate onboarding with:

```sql
IF EXISTS (
  SELECT 1 FROM public.family_members
  WHERE user_id = v_uid AND status = 'ACTIVE'
) THEN
  RAISE EXCEPTION 'ALREADY_HAS_ACTIVE_FAMILY';
END IF;
```

This is not enough under concurrency. Two simultaneous requests for the same new user can both pass the check before either inserts into `family_members`, creating two families.

## Required Fix

Because MVP currently allows one active family per user, enforce it at the database level:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS uq_family_members_one_active_family_per_user
ON public.family_members(user_id)
WHERE status = 'ACTIVE';
```

Also serialize onboarding per auth user before the existence check:

```sql
PERFORM 1 FROM auth.users WHERE id = v_uid FOR UPDATE;
```

Then keep the existing `ALREADY_HAS_ACTIVE_FAMILY` check for a friendly error.

Optionally handle `unique_violation` inside the function and re-raise `ALREADY_HAS_ACTIVE_FAMILY`, but the unique index is the non-negotiable protection.

## Recommended Hardening

Restrict function execution explicitly:

```sql
REVOKE ALL ON FUNCTION public.fn_create_initial_family(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_create_initial_family(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_create_initial_family(text, text) TO authenticated;
```

## Gate Status

- Onboarding logic: accepted except concurrency race.
- Tests: syntax accepted, pending real DB execution.
- Phase 3 remains blocked until the unique active-family protection is added.

