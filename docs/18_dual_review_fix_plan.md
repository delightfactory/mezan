# Dual Review Fix Plan Before Phase 3

**Date:** 2026-05-01  
**Decision:** Phase 3 is blocked pending database fixes.

This plan merges the independent Claude review with the Codex review.

## Executive Decision

`BLOCKED_PENDING_FIXES`

Do not start TypeScript types until the Priority 1 fixes are complete and re-reviewed.

## Priority 1 - Must Fix Before Phase 3

### P1-1. Fix correction/reversal reconciliation semantics

Problem:

- `fn_correct_transaction` marks the original transaction as `REVERSED`.
- It also inserts a posted `REVERSAL` transaction.
- `fn_recalculate_wallet_balance` only counts `status = 'POSTED'`.
- This can make reconciliation mathematically wrong.

Required fix:

- Choose one consistent model:
  - keep original as `POSTED` and insert a posted reversal that offsets it, or
  - mark original as `REVERSED` and do not include the reversal row in balance reconstruction, or
  - model reversal rows with a link/status rule that reconciliation understands.
- Update `fn_recalculate_wallet_balance` accordingly.
- Update tests for income, expense, and transfer correction.

### P1-2. Protect cached/sensitive financial columns from direct client updates

Problem:

RLS permits direct updates to tables containing derived/sensitive financial state.

Protected columns must not be directly mutated by client writes:

- `wallets.balance`
- `budgets.spent_amount`
- `debts.remaining_amount`
- payment reference fields such as `paid_transaction_id`, `transaction_id`
- sensitive status transitions for debts, gameya, occurrences where side effects are required

Required fix:

- Add triggers that reject protected column changes unless performed by controlled RPC pathways, or remove direct update policies and replace with narrow RPCs for editable metadata.
- At minimum, allow owners to update wallet metadata (`name`, `icon`, `sort_order`, `is_archived`) but not `balance`.

### P1-3. Harden SECURITY DEFINER helper function exposure

Problem:

PostgreSQL grants execute on functions to `PUBLIC` by default. Internal helpers are currently callable unless explicitly revoked.

Required fix:

- Explicitly revoke helper execution from `PUBLIC` and `anon`:
  - `public._require_member(uuid, public.member_role[])`
  - `public.get_my_family_ids()`
  - `public.user_has_role(uuid, public.member_role[])`
- Grant only as needed after runtime verification. If RLS requires caller execution, document the decision.

### P1-4. Fix explicit function grants with signatures

Problem:

`GRANT EXECUTE ON FUNCTION public.fn_record_income TO authenticated;` may fail because PostgreSQL generally expects a full function signature.

Required fix:

- Replace function grants/revokes with explicit signatures for every RPC and helper.

### P1-5. Tighten `GAMEYA_PAYOUT` ledger constraint

Problem:

`GAMEYA_PAYOUT` is now used transfer-style with both `from_wallet_id` and `to_wallet_id`, but the constraint requires only `to_wallet_id`.

Required fix:

- Change the constraint so `GAMEYA_PAYOUT` requires both wallets and different IDs.

### P1-6. Decide and enforce negative wallet policy

Decision for MVP:

- Wallet balances must not be negative.

Required fix:

- Add database-level protection: `CHECK (balance >= 0)` for all wallets.
- Keep RPC balance checks.
- Add tests for overspending and concurrent spending behavior where possible.

### P1-7. Fix budget/effective_at handling in correction

Problem:

Adjustment transactions default to `now()` while budget updates may use original `effective_at`.

Required fix:

- Either set the replacement transaction `effective_at = v_o.effective_at`, or add an explicit replacement effective date parameter and update budgets using the replacement transaction's own date.
- For MVP, prefer preserving original `effective_at`.

## Priority 2 - Should Fix Before First Real Users

### P2-1. Validate category direction and ownership in RPCs

Required fix:

- `fn_record_income`: category must be `INCOME`, system or same family, not archived.
- `fn_record_expense`: category must be `EXPENSE`, system or same family, not archived.
- transfers/allocation should use `TRANSFER` category or allow null deliberately.

### P2-2. Add opening balance RPC

Required fix:

- Add `fn_record_opening_balance` so initial balances enter through ledger, not fake income.

### P2-3. Add debt creation RPCs

Required fix:

- `fn_record_borrowed_money`: creates debt + `LOAN_RECEIVE` + wallet increase.
- `fn_record_lent_money`: creates debt + `LOAN_DISBURSE` + wallet decrease.

### P2-4. Add gameya installment RPC

Required fix:

- `fn_record_gameya_installment`: transfer from real wallet to gameya reserve wallet, update turn status, link transaction.

### P2-5. Guard gameya reserve overfunding

Required fix:

- In payout, use `v_paid := LEAST(v_alloc_w.balance, v_g.payout_amount)`.
- Reject or leave surplus explicitly; do not silently treat surplus as payout.

### P2-6. Last owner protection

Required fix:

- Prevent demoting/suspending/removing the last active owner in a family.

## Required Test Updates

- Correction reconciliation for income, expense, transfer.
- Direct update to `wallets.balance` is blocked.
- Direct update to `budgets.spent_amount` is blocked.
- Direct update to `debts.remaining_amount` is blocked.
- Category direction mismatch rejected.
- Opening balance reconciliation.
- Borrowed money and lent money creation.
- Gameya installment and payout lifecycle.
- Anon cannot execute exposed RPCs.
- Fix `atomic_financial_operations.sql` direct insert test to use `created_by = family_members.id`, not auth user id.

## Decisions Recorded

- MVP supports one active family per user.
- MVP wallet balances cannot be negative.
- System categories are shared via `family_id IS NULL`; they are not copied on onboarding.
- Generic correction is limited to simple `INCOME`, `EXPENSE`, and `TRANSFER`.

