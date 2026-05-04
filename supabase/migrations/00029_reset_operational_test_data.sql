-- =============================================================================
-- Mezan: 00029_reset_operational_test_data.sql
-- Purpose: Clear test/runtime operational data while preserving reference data.
--
-- PRESERVED (dependency/reference data):
-- - auth.users
-- - public.family_groups
-- - public.family_members
-- - public.categories (system and family category definitions)
-- - enum/domain/function/RLS/schema definitions
--
-- CLEARED (runtime/operational data):
-- - wallets and all cached balances
-- - ledger transactions and transaction links
-- - commitments and occurrences
-- - sinking funds
-- - debts and debt payments
-- - gameya circles, turns, and installments
-- - budgets
-- - audit events and notifications
--
-- WARNING:
-- This migration is intentionally destructive for operational test data.
-- Do not apply it to a production database that contains real user financial data.
-- =============================================================================

TRUNCATE TABLE
  public.transaction_links,
  public.debt_payments,
  public.commitment_occurrences,
  public.gameya_installments,
  public.gameya_turns,
  public.audit_events,
  public.notifications,
  public.budgets,
  public.sinking_funds,
  public.commitments,
  public.debts,
  public.gameya_circles,
  public.ledger_transactions,
  public.wallets
RESTART IDENTITY;

