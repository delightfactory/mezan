# Phase 2 Migration Review V4

**Date:** 2026-05-01  
**Decision:** Migration SQL static review accepted; verification script needs one fix before Phase 2 can be considered ready for later DB execution.

## Accepted Fixes

- `fn_receive_gameya_payout` now returns real persisted transaction IDs using:
  - `reserve_transfer_txn_id`
  - `loan_receive_txn_id`
- The early gameya remainder now uses `LOAN_RECEIVE`, which matches receiving borrowed funds and creating a liability.
- No random UUID is returned from the financial RPC.
- Generic correction remains restricted to `INCOME`, `EXPENSE`, and `TRANSFER`.
- `supabase db reset` reaches Docker inspection, so the previous config parse blocker is resolved.

## Remaining Fix For Verification Script

`supabase/tests/atomic_financial_operations.sql` still inserts categories using non-existent columns:

```sql
INSERT INTO public.categories (id, family_id, name, type) ...
```

The real schema uses:

```sql
name_ar, name_en, direction, behavior
```

Acceptance condition:

- Replace the test category inserts with valid schema columns, for example:

```sql
INSERT INTO public.categories
  (id, family_id, name_ar, name_en, direction, behavior)
VALUES
  (v_cat_income, v_family_id, 'مرتب اختبار', 'Test Salary', 'INCOME', 'SYSTEM'),
  (v_cat_expense, v_family_id, 'مصروف اختبار', 'Test Expense', 'EXPENSE', 'VARIABLE_BUDGETED');
```

## Gate Status

- Migration files: accepted by static review, pending real DB execution later.
- Verification script: not accepted until the category insert fix is applied.
- Phase 3 should wait until the verification script is corrected, even if DB execution itself is deferred until a Supabase/Docker environment is available.

