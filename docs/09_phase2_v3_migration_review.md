# Phase 2 Migration Review V3

**Date:** 2026-05-01  
**Decision:** Not approved for Phase 3 yet

## What Improved

- `supabase db reset` now reaches Docker inspection. Config parsing is no longer the active blocker.
- Generic correction is restricted to `INCOME`, `EXPENSE`, and `TRANSFER`.
- Gameya payout now transfers only the actual reserve balance from allocated wallet to real wallet, which fixes the previous reserve reconciliation issue.
- Debt direction handling remains improved.

## Remaining Blocking Findings

### 1. Gameya early-payout remainder uses the wrong transaction type and may return a fake ID

In `fn_receive_gameya_payout`, the unpaid remainder of an early gameya payout is inserted as `LOAN_PAYMENT_IN`.

This is semantically wrong: the family is receiving borrowed money and creating a liability, so the ledger type should be `LOAN_RECEIVE`, not a loan payment received. `LOAN_PAYMENT_IN` means someone is paying back money the family previously lent.

The function also returns `COALESCE(v_id, gen_random_uuid())`. If `v_paid = 0`, the function can return a UUID that is not a real ledger transaction. Financial RPCs must return actual persisted references.

Acceptance condition:

- Use `LOAN_RECEIVE` for the early-payout remainder.
- Capture the ID of that ledger transaction.
- Return a real transaction ID, or change the return type to include both `reserve_transfer_txn_id` and `loan_receive_txn_id`.
- Ensure audit details reference real IDs only.

### 2. Atomic test file is still not executable as written

`supabase/tests/atomic_financial_operations.sql` inserts into `family_members` with a random `user_id`, but `family_members.user_id` references `auth.users(id)`. The test does not create an `auth.users` row.

It also passes random category IDs to RPCs without inserting matching `categories`, so later ledger inserts with `category_id` may fail for the wrong reason.

Acceptance condition:

- Create a valid test auth user, or document and implement a supported test harness for `auth.uid()`.
- Insert valid test categories or pass `NULL` where allowed.
- Make all test failures prove the intended invariant, not unrelated FK failures.

### 3. Direct insert/RLS test is still not implemented

The test file comments that direct insert is blocked by lack of policies, but it does not verify that as the `authenticated` role.

Acceptance condition:

- Add a test that switches to an authenticated context/role where possible and proves direct insert into `ledger_transactions` fails.
- If this cannot be executed in a plain SQL script, document the exact manual/API test required and expected error.

## Non-Blocking Follow-Up

- `GAMEYA_PAYOUT` is now used transfer-style with both `from_wallet_id` and `to_wallet_id`, while the table comment says it credits a wallet. The behavior is acceptable if documented, but the ledger constraint/comment should be clarified.
- Consider adding a guard for `v_paid > payout_amount` in gameya payout to catch overfunded reserve anomalies.

## Current Gate Status

Phase 2 remains close, but still blocked. Fix the real transaction ID/type issue in gameya and make the tests executable and meaningful before requesting another review.

