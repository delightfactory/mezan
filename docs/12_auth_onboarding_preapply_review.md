# Auth And Onboarding Pre-Apply Review

**Date:** 2026-05-01  
**Decision:** Add an auth/onboarding migration before applying migrations to Supabase.

## Why This Gate Exists

The financial schema is ready by static review, but a real application also needs a complete user birth flow:

1. user signs up in Supabase Auth
2. database creates or prepares an application identity path
3. user gets a family
4. user becomes `OWNER`
5. initial wallets/categories/settings can be created safely
6. RLS can immediately resolve membership through `auth.uid()`

Currently, `family_members.user_id` references `auth.users(id)`, and RLS depends on `family_members`, but there is no dedicated auth trigger or onboarding RPC in the migrations.

## Current Gap

Existing migrations include:

- `family_groups`
- `family_members`
- RLS helper functions using `auth.uid()`
- an open `family_groups_insert` policy
- a first-member exception in `family_members_insert`

Missing:

- `handle_new_user` trigger or explicit onboarding RPC
- deterministic creation of first family and OWNER membership
- default wallet setup
- optional copying/using system categories
- onboarding status tracking
- safe idempotency for retried signup/onboarding

## Recommended Design

Use an explicit onboarding RPC as the primary MVP path:

`public.fn_create_initial_family(p_family_name text default null, p_display_name text default null)`

The function should:

- require `auth.uid()` to be non-null
- be `SECURITY DEFINER SET search_path = public, pg_temp`
- be idempotent or fail clearly if the user already owns/has an active family
- create `family_groups`
- create `family_members` with role `OWNER`, status `ACTIVE`
- create default wallets:
  - `كاش`
  - `بنك`
  - optionally `طوارئ` as `ALLOCATED`
- insert an audit event if possible after membership exists
- return `family_id` and `member_id`

Do not rely only on direct client inserts into `family_groups` and `family_members` for onboarding.

## Optional Auth Trigger

An `auth.users` trigger may be added only for minimal user-profile preparation. Avoid doing heavy business setup in the trigger if product onboarding needs user choices.

If used, it should:

- not create financial wallets without user consent unless this is the accepted product choice
- be idempotent
- not break signup if optional metadata is missing

## RLS Adjustments

After adding onboarding RPC:

- Consider removing broad `family_groups_insert WITH CHECK (true)`.
- Consider removing the first-member direct insert exception in `family_members_insert`.
- Prefer RPC-only first family creation to avoid orphan family rows or mismatched first owners.

## Pre-Apply Requirement

Before applying migrations to Supabase:

- Add onboarding migration after current financial migrations, or insert it before RLS if policy dependencies require it.
- Add verification tests for:
  - new authenticated user can create initial family through RPC
  - unauthenticated call fails
  - user becomes OWNER
  - RLS can read the created family after onboarding
  - duplicate onboarding is handled safely
  - direct orphan family/member creation is not allowed if RPC-only policy is adopted

