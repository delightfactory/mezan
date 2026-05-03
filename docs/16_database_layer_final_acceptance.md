# Database Layer Final Acceptance

**Date:** 2026-05-01  
**Decision:** Database layer is accepted as a complete migration package ready for later Supabase application and execution verification.

## Accepted Scope

The database layer now covers:

- Auth onboarding entry point.
- RPC-only first family creation.
- OWNER membership creation.
- Default wallets.
- Family/member RLS hardening.
- Financial ledger, wallets, budgets, commitments, debts, gameya, audit, and notifications.
- Atomic RPCs for critical financial operations.
- Immutability guards.
- Verification scripts outside production migrations.

## Final Preconditions Before Real Apply

Before applying to a real Supabase project:

- Use a disposable/test Supabase project first.
- Confirm the target project explicitly.
- Do not print or share `.env` values.
- Run migrations.
- Run:
  - `supabase/tests/auth_onboarding_test.sql`
  - `supabase/tests/atomic_financial_operations.sql`
- Capture migration and test outputs.

## Phase 3 Is Now Allowed

Phase 3 may begin with TypeScript types only.

Allowed:

- Database type mirror based on accepted migrations.
- SQL enum mirrors.
- Domain DTOs.
- RPC input/output types.
- Zod or equivalent validation schemas.
- Documentation of the future Supabase type generation command.

Not allowed yet:

- Services.
- UI.
- Migration changes without a separate review.
- Assuming manual types are final after a real DB is applied.

