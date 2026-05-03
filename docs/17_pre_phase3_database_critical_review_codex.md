# Pre-Phase 3 Database Critical Review - Codex

**Date:** 2026-05-01  
**Decision:** Do not start Phase 3 until the findings below are triaged.

## Critical Findings

### 1. Correction flow breaks ledger reconciliation

`fn_correct_transaction` changes the original transaction status from `POSTED` to `REVERSED`, then inserts a posted `REVERSAL` transaction with swapped wallets.

`fn_recalculate_wallet_balance` only includes `status = 'POSTED'`. This means the original transaction is excluded, while its reversal remains included. Reconciliation will subtract the original amount twice in effect.

Example:

- Original income: +100 to wallet.
- Correction marks original as `REVERSED`.
- Reversal row subtracts 100.
- Recalculation sees only the reversal, not the original, so the wallet becomes -100 relative to the pre-transaction base.

Required decision:

- Either keep original transactions included in reconciliation and use reversal rows to offset them, or
- exclude both original and reversal and keep only the replacement transaction.

Do not proceed until correction semantics are made mathematically consistent.

### 2. Direct RLS updates can mutate cached or sensitive financial state

RLS currently allows direct `UPDATE` on tables such as:

- `wallets`
- `budgets`
- `debts`
- `gameya_circles`
- `gameya_turns`
- `commitment_occurrences`

This can allow clients to mutate cached balances, spent amounts, remaining debt, statuses, or payment references outside atomic RPCs.

Required fix:

- Either make sensitive financial tables RPC-only for updates, or
- add triggers that block direct mutation of protected columns such as `wallets.balance`, `budgets.spent_amount`, `debts.remaining_amount`, ledger/payment reference fields, and financial statuses except through approved functions.

### 3. Function grants in `00016` may be syntactically invalid

`00016_financial_functions.sql` uses grants like:

```sql
GRANT EXECUTE ON FUNCTION public.fn_record_income TO authenticated;
```

PostgreSQL generally requires function argument signatures for `GRANT EXECUTE ON FUNCTION` when granting a specific function.

Required fix:

- Use explicit signatures for all function grants/revokes, or use a safe schema-level grant strategy.

### 4. Internal SECURITY DEFINER helper functions are executable by default

Functions such as:

- `get_my_family_ids`
- `user_has_role`
- `_require_member`

are `SECURITY DEFINER`. PostgreSQL grants function execute to `PUBLIC` by default unless revoked.

Required fix:

- Explicitly revoke helper execution from `PUBLIC` and `anon`.
- Grant only where needed. If helpers are only used in policies/functions, avoid exposing them as public RPCs.

## High Findings

### 5. Category direction is not validated against transaction type

RPCs accept `category_id`, but they do not verify:

- category belongs to the same family or is system-level
- category direction matches transaction type
- category is not archived

This can record an expense with an income category, or use another family's category.

### 6. Cross-family consistency is not enforced on several foreign keys

Many tables carry `family_id` and reference another family-scoped table, but there is no composite FK or trigger to ensure both sides belong to the same family.

Examples:

- budgets category
- commitments category/wallet
- sinking fund wallet
- gameya wallet
- debt payment transaction

RPCs cover some paths, but direct admin/setup writes can drift.

### 7. Missing debt creation flows

The schema supports debts, but there are no atomic RPCs for:

- borrowing money and increasing a wallet (`LOAN_RECEIVE`)
- lending money and decreasing a wallet (`LOAN_DISBURSE`)

Direct inserts into `debts` do not create matching ledger movement. This is acceptable only for opening balances/imports, not normal app operations.

### 8. Gameya overfunding is not guarded

`fn_receive_gameya_payout` does not block `reserve_wallet.balance > payout_amount`. This anomaly would make `v_rem` negative and should be rejected or handled explicitly.

### 9. Owner/member administration can remove governance safety

`family_members_update` lets an owner update family members without a guard that prevents:

- demoting the last owner
- suspending the last owner
- changing ownership in invalid ways

This can lock a family out of administration.

## Medium Findings

### 10. No recurrence generation mechanism

Commitments and occurrences exist, but there is no function/job to generate occurrences from frequency.

### 11. Safe-to-spend is still incomplete

`fn_calculate_safe_to_spend` currently subtracts allocated wallets and all upcoming/overdue commitments, but does not fully account for:

- financial cycle windows
- debts installments
- gameya installments
- due dates and priority handling

### 12. Audit action naming is imprecise

Onboarding logs `MEMBER_INVITED`, but the event is actually initial owner creation. Consider adding `FAMILY_CREATED` or `ONBOARDING_COMPLETED`.

