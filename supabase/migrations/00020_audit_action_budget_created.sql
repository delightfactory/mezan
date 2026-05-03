-- =============================================================================
-- Mezan: 00020_audit_action_budget_created.sql
-- Safely add BUDGET_CREATED to audit_action enum before use.
-- =============================================================================

ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'BUDGET_CREATED';
