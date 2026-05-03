-- =============================================================================
-- Mezan: 00015_indexes.sql
-- Performance indexes for RLS predicates, financial queries, and dashboards.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- RLS Predicate Support (Critical for performance)
-- ---------------------------------------------------------------------------
-- This is the most important index: every RLS policy checks membership.
CREATE INDEX idx_family_members_user_status
  ON public.family_members(user_id, family_id)
  WHERE status = 'ACTIVE';

-- ---------------------------------------------------------------------------
-- Ledger Queries
-- ---------------------------------------------------------------------------
-- Primary dashboard query: recent transactions per family.
CREATE INDEX idx_ledger_family_effective
  ON public.ledger_transactions(family_id, effective_at DESC);

-- Wallet statement: transactions for a specific source wallet.
CREATE INDEX idx_ledger_family_from_wallet
  ON public.ledger_transactions(family_id, from_wallet_id, effective_at DESC)
  WHERE from_wallet_id IS NOT NULL;

-- Wallet statement: transactions for a specific destination wallet.
CREATE INDEX idx_ledger_family_to_wallet
  ON public.ledger_transactions(family_id, to_wallet_id, effective_at DESC)
  WHERE to_wallet_id IS NOT NULL;

-- Category analysis: spending per category over time.
CREATE INDEX idx_ledger_family_category
  ON public.ledger_transactions(family_id, category_id, effective_at DESC);

-- Active (non-reversed) transactions filter.
CREATE INDEX idx_ledger_posted
  ON public.ledger_transactions(family_id, status)
  WHERE status = 'POSTED';

-- ---------------------------------------------------------------------------
-- Wallets
-- ---------------------------------------------------------------------------
CREATE INDEX idx_wallets_family
  ON public.wallets(family_id)
  WHERE NOT is_archived;

-- ---------------------------------------------------------------------------
-- Commitment Occurrences
-- ---------------------------------------------------------------------------
CREATE INDEX idx_occurrences_family_due
  ON public.commitment_occurrences(family_id, due_date, status);

-- ---------------------------------------------------------------------------
-- Budgets
-- ---------------------------------------------------------------------------
CREATE INDEX idx_budgets_family_cycle
  ON public.budgets(family_id, cycle_start, category_id);

-- ---------------------------------------------------------------------------
-- Debts
-- ---------------------------------------------------------------------------
CREATE INDEX idx_debts_family_active
  ON public.debts(family_id)
  WHERE status = 'ACTIVE';

CREATE INDEX idx_debt_payments_debt
  ON public.debt_payments(debt_id, paid_at DESC);

-- ---------------------------------------------------------------------------
-- Gam'eya
-- ---------------------------------------------------------------------------
CREATE INDEX idx_gameya_family_active
  ON public.gameya_circles(family_id)
  WHERE status NOT IN ('COMPLETED', 'CANCELLED');

CREATE INDEX idx_gameya_turns_due
  ON public.gameya_turns(gameya_id, due_date, status);

-- ---------------------------------------------------------------------------
-- Audit
-- ---------------------------------------------------------------------------
CREATE INDEX idx_audit_family_created
  ON public.audit_events(family_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------
CREATE INDEX idx_notifications_recipient_unread
  ON public.notifications(recipient_member_id, created_at DESC)
  WHERE NOT is_read;

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------
CREATE INDEX idx_categories_family
  ON public.categories(family_id)
  WHERE NOT is_archived;

-- System categories (seed templates).
CREATE INDEX idx_categories_system
  ON public.categories(direction, behavior)
  WHERE family_id IS NULL AND is_system = true;

-- ---------------------------------------------------------------------------
-- Transaction Links
-- ---------------------------------------------------------------------------
CREATE INDEX idx_txn_links_source
  ON public.transaction_links(source_transaction_id);

CREATE INDEX idx_txn_links_related
  ON public.transaction_links(related_transaction_id);

-- ---------------------------------------------------------------------------
-- Sinking Funds
-- ---------------------------------------------------------------------------
CREATE INDEX idx_sinking_funds_family
  ON public.sinking_funds(family_id)
  WHERE is_active;

-- ---------------------------------------------------------------------------
-- Commitments
-- ---------------------------------------------------------------------------
CREATE INDEX idx_commitments_family_active
  ON public.commitments(family_id)
  WHERE is_active;
