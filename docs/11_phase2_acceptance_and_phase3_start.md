# Phase 2 Acceptance And Phase 3 Start

**Date:** 2026-05-01  
**Decision:** Phase 2 is accepted as migration files ready for later database application.

## Acceptance Scope

Phase 2 is accepted by static review and file-level verification.

This means:

- Migration files are structurally ready.
- Financial atomicity rules are represented in RPCs.
- Direct client inserts into critical ledger-linked tables are blocked by missing insert policies.
- Gameya payout is ledger-reconcilable.
- Debt directions are handled separately.
- Generic correction is restricted to simple MVP transaction types.
- Verification script is outside production migrations and matches the current schema.

This does not mean:

- The migrations have been applied to a real Supabase database.
- `supabase db reset` has passed.
- RLS behavior has been proven by a live authenticated client request.

Final execution approval remains pending until a Supabase/Docker or hosted test database is available.

## Phase 3 Boundary

Phase 3 may begin as a schema-derived types phase only.

Allowed:

- Create TypeScript database type files from the accepted schema shape.
- Create domain DTOs and enums that mirror SQL enums.
- Create validation schemas for service inputs.
- Document type-generation commands for later execution against Supabase.
- Add TODO markers where generated types must be replaced by actual Supabase generated output after DB application.

Not allowed:

- Change migration logic casually while working on types.
- Build services or UI before Phase 3 review.
- Invent types that conflict with SQL names, enum values, nullability, or money precision.
- Treat generated/manual types as final until regenerated from an applied database.

## Required Phase 3 Deliverables

- `src/types/database.ts` or equivalent generated-type placeholder aligned with the migrations.
- Domain type layer for wallets, ledger transactions, commitments, debts, gameya, budgets, and safe-to-spend.
- Validation schemas for RPC inputs.
- Phase 3 review report mapping SQL contracts to TypeScript contracts.

