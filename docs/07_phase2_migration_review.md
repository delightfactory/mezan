# Phase 2 Migration Review

**Date:** 2026-05-01  
**Decision:** Not approved for Phase 3 yet

## Summary

The migration set is a strong first pass and includes the expected schema, RLS, seed categories, and financial RPCs. However, Phase 3 is blocked because several findings can break financial integrity or prevent local verification.

## Blocking Findings

### 1. Local migration reset does not run

`supabase db reset` failed before applying migrations because the installed Supabase CLI is `2.23.4` and cannot parse the generated `supabase/config.toml`.

Failure included invalid keys such as:

- `db.migrations.enabled`
- `db.health_timeout`
- `storage.s3_protocol`
- `auth.rate_limit.web3`
- `auth.oauth_server`

Acceptance condition:

- Align `supabase/config.toml` with the installed CLI, or upgrade the CLI.
- Run `supabase db reset` successfully from a clean local database.

Follow-up check after partial config patch:

- `supabase db reset` still fails with CLI `2.23.4` because these keys remain unsupported:
  - `db.network_restrictions`
  - `storage.analytics`
  - `storage.vector`
  - `auth.external.apple.email_optional`

### 2. Direct client inserts can bypass atomic financial RPCs

`00014_rls_policies.sql` allows direct inserts into financial/audit-linked tables:

- `ledger_transactions`
- `transaction_links`
- `debt_payments`

This conflicts with the atomicity rule because a client can insert a ledger row without the matching wallet/debt/budget side effects.

Acceptance condition:

- Remove direct client insert policies from ledger and side-effect tables.
- Route all financial writes through RPCs only.
- Keep direct inserts only for non-financial setup tables where safe.

### 3. `fn_record_debt_payment` handles `LENT_TO` incorrectly

For `LENT_TO`, repayment means someone pays the family back, so the wallet should increase and the ledger should use `to_wallet_id`.

Current function uses `from_wallet_id` and decreases wallet balance even when `v_tt = 'LOAN_PAYMENT_IN'`.

Acceptance condition:

- Split debt payment handling by direction:
  - `BORROWED_FROM`: debit wallet with `LOAN_PAYMENT_OUT`.
  - `LENT_TO`: credit wallet with `LOAN_PAYMENT_IN`.
- Add tests for both debt directions.

### 4. `fn_correct_transaction` uses generic `ADJUSTMENT` outside ledger constraints

`ADJUSTMENT` has no directional constraints in `ledger_transactions`, and the function reuses the original wallet direction while manually applying balance effects. This makes reconciliation ambiguous and likely wrong for some transaction types.

Acceptance condition:

- Either model adjustment as the original transaction type, or add explicit constraints and balance semantics for `ADJUSTMENT`.
- Add correction tests for income, expense, transfer, debt payment, and gameya payout.

### 5. Gameya payout can create inconsistent accounting

`fn_receive_gameya_payout` sets the gameya reserve wallet balance to zero without inserting a ledger transaction for clearing that reserve. Reconciliation from the ledger will later reconstruct a different balance.

It also calculates paid-so-far from turn statuses, not from the reserve wallet or posted ledger, so a status drift can produce the wrong debt.

Acceptance condition:

- Clear the reserve through a ledger-backed transaction or a linked reversal/transfer pattern.
- Calculate paid/reserve from posted ledger or locked wallet balance.
- Add reconciliation test after payout.

## Important Non-Blocking Findings

- `SECURITY DEFINER` functions use `SET search_path = public`; better hardening is `SET search_path = public, pg_temp` or an unexposed private schema for helpers.
- `EXECUTE` grants to `authenticated` are acceptable only if every function validates family membership and role internally. Re-check all helper functions and revoke execute on internal helpers unless explicitly needed.
- `CREATE RULE ... DO INSTEAD NOTHING` silently hides failed deletes/updates. Prefer triggers that raise exceptions for audit clarity.
- `fn_calculate_safe_to_spend` is too simplified for MVP acceptance because it omits debts, gameya installments, and financial cycle windows.

## Required Evidence Before Approval

- Successful `supabase db reset`.
- SQL tests for:
  - direct ledger insert blocked from authenticated client role.
  - failed mid-operation leaves no partial writes.
  - concurrent wallet spending cannot overdraw.
  - debt payment for both `BORROWED_FROM` and `LENT_TO`.
  - correction for income, expense, and transfer.
  - gameya payout followed by wallet reconciliation.
- Updated verification report mapping each fix to the checklist.

## Test Placement Guidance

Do not add verification tests as a production migration such as `00019_atomic_tests.sql` unless the project intentionally wants tests to run in every deployed environment. Prefer one of these:

- `supabase/tests/atomic_financial_operations.sql`
- `supabase/verification/atomic_financial_operations.sql`
- a documented local-only script that wraps setup and assertions in a transaction and rolls back test data

The production migration history should create schema and seed/reference data only. Test scripts should prove the migration, not become part of the deployed schema path.
