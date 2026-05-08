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
-- - commitment partial-payment history
-- - transaction receipt/attachment metadata
-- - sinking funds
-- - debts, debt payments, and debt events
-- - gameya circles, turns, and installments
-- - budgets
-- - family invitations
-- - audit events and notifications
--
-- WARNING:
-- This migration is intentionally destructive for operational test data.
-- Do not apply it to a production database that contains real user financial data.
--
-- NOTE:
-- This SQL reset clears receipt metadata in public.transaction_attachments.
-- Supabase Storage object rows are intentionally not deleted here because
-- Supabase protects storage.objects from direct SQL deletion. If receipt files
-- need to be physically removed, use the Supabase Storage API / service-role
-- cleanup flow for the private expense-receipts bucket.
-- =============================================================================

DO $$
DECLARE
  v_tables text[];
  v_truncate_sql text;
BEGIN
  /*
    Keep this reset script safe both when it is replayed in migration order
    and when it is run manually against a later development database.

    Some operational tables were introduced after this migration number
    (for example commitment_payments, debt_events, transaction_attachments).
    Referencing them directly would break a clean db reset at migration 00029,
    so we only truncate the runtime tables that currently exist.
  */
  v_tables := ARRAY[
    'public.transaction_attachments',
    'public.transaction_links',
    'public.commitment_payments',
    'public.debt_due_occurrences',
    'public.debt_payments',
    'public.debt_events',
    'public.commitment_occurrences',
    'public.gameya_installments',
    'public.gameya_turns',
    'public.family_invitations',
    'public.audit_events',
    'public.notifications',
    'public.budgets',
    'public.sinking_funds',
    'public.commitments',
    'public.debts',
    'public.gameya_circles',
    'public.ledger_transactions',
    'public.wallets'
  ];

  SELECT 'TRUNCATE TABLE ' || string_agg(regclass_table::text, ', ') || ' RESTART IDENTITY'
  INTO v_truncate_sql
  FROM (
    SELECT to_regclass(table_name) AS regclass_table
    FROM unnest(v_tables) AS t(table_name)
  ) existing_tables
  WHERE regclass_table IS NOT NULL;

  IF v_truncate_sql IS NOT NULL THEN
    EXECUTE v_truncate_sql;
  END IF;
  RAISE NOTICE 'Operational SQL data reset completed. Receipt files in Storage were not deleted; clean expense-receipts via Storage API if needed.';
END $$;
