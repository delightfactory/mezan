# Phase 2 Migration Review V2

**Date:** 2026-05-01  
**Decision:** Not approved for Phase 3 yet

## What Improved

- `supabase db reset` now gets past config parsing and fails only because Docker Desktop is unavailable in this environment.
- Direct insert policies were removed from `ledger_transactions`, `transaction_links`, and `debt_payments`.
- `SECURITY DEFINER` functions now use `SET search_path = public, pg_temp`.
- Debt payment direction was split between `BORROWED_FROM` and `LENT_TO`.
- Immutability protection now raises explicit exceptions instead of silently ignoring writes.
- Tests were moved outside production migrations.

## Remaining Blocking Findings

### 1. Gameya payout is still not ledger-reconcilable

`fn_receive_gameya_payout` records a single `GAMEYA_PAYOUT` transaction with `amount = payout_amount`, `from_wallet_id = reserve_wallet`, and `to_wallet_id = real_wallet`. It then adds the full payout to the real wallet and sets the reserve wallet balance to zero.

This only reconciles if the reserve already equals the full payout. In the early-payout case, reserve balance is lower than payout amount, so ledger reconstruction will produce:

- reserve wallet: `reserve_balance - payout_amount` which becomes negative
- real wallet: `+ payout_amount`

But cached balance is forced to reserve = 0. That violates "ledger is source of truth".

Acceptance condition:

- Model gameya payout as ledger-consistent entries:
  - transfer/deallocate only the actual reserve balance from reserve wallet to real wallet, and
  - record the remaining amount as external inflow/loan receive to the real wallet while creating the debt.
- Or introduce explicit ledger semantics and constraints that reconcile exactly.
- Add verification that `fn_recalculate_wallet_balance(reserve_wallet)` returns zero after early payout.

### 2. Atomic tests do not currently prove the required risks

`supabase/tests/atomic_financial_operations.sql` currently focuses on immutability guards only. It does not test:

- direct ledger insert blocked for authenticated client role
- failed RPC rollback/no partial writes
- debt payment for both directions
- gameya payout reconciliation
- correction for income/expense/transfer

It also appears incompatible with the schema:

- inserts into `family_groups` using non-existent columns `current_cycle_start`, `current_cycle_end`
- inserts into `ledger_transactions` without required `created_by`

Acceptance condition:

- Rewrite the test file so it matches the actual schema.
- Use valid test setup with `auth.users`/`family_members` or document the exact execution role/claims required.
- Add the required tests above.

### 3. Correction flow remains too broad for MVP financial integrity

`fn_correct_transaction` can now create an adjustment using the original transaction type, which is better than generic `ADJUSTMENT`. However it still allows correction of complex linked transactions such as gameya payout and debt payment without reversing their side effects in `debts`, `debt_payments`, `gameya_circles`, or `gameya_turns`.

Acceptance condition:

- Either restrict generic correction to simple `INCOME`, `EXPENSE`, and `TRANSFER` only for MVP, or implement type-specific correction flows for debt/gameya/commitments.
- Add tests for every allowed correction type.

## Non-Blocking Follow-Up

- Consider revoking direct execute on internal helper functions such as `_require_member`, unless needed externally.
- `fn_calculate_safe_to_spend` is still intentionally simplified and should be expanded before product MVP acceptance.

## Current Gate Status

Phase 2 is close, but not ready for TypeScript types. Fix the remaining three blockers, then request another review.

