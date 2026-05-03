-- =============================================================================
-- Mezan: 00007_transaction_links.sql
-- Links between transactions for reversal, adjustment, and audit trail.
-- =============================================================================

CREATE TABLE public.transaction_links (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id               UUID NOT NULL
                          REFERENCES public.family_groups(id) ON DELETE RESTRICT,
  source_transaction_id   UUID NOT NULL
                          REFERENCES public.ledger_transactions(id) ON DELETE RESTRICT,
  related_transaction_id  UUID NOT NULL
                          REFERENCES public.ledger_transactions(id) ON DELETE RESTRICT,
  -- REVERSAL: related reverses source.
  -- ADJUSTMENT: related adjusts source (after reversal).
  -- PAIR: two sides of same operation (e.g. allocation pair).
  -- ALLOCATION: income → commitment allocation link.
  link_type               TEXT NOT NULL
                          CONSTRAINT valid_link_type CHECK (
                            link_type IN ('REVERSAL', 'ADJUSTMENT', 'PAIR', 'ALLOCATION')
                          ),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Cannot link a transaction to itself.
  CONSTRAINT no_self_link CHECK (source_transaction_id != related_transaction_id)
);

COMMENT ON TABLE public.transaction_links IS 'Audit trail links between transactions: reversals, adjustments, and paired operations.';
