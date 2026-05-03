-- =============================================================================
-- Mezan: 00008_commitments.sql
-- Recurring/scheduled obligations and their per-cycle occurrences.
-- =============================================================================

CREATE TABLE public.commitments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id       UUID NOT NULL
                  REFERENCES public.family_groups(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  category_id     UUID REFERENCES public.categories(id) ON DELETE SET NULL,
  amount          NUMERIC(14,2) NOT NULL
                  CONSTRAINT positive_commitment_amount CHECK (amount > 0),
  frequency       public.commitment_freq NOT NULL,
  -- Preferred wallet for payment.
  wallet_id       UUID REFERENCES public.wallets(id) ON DELETE SET NULL,
  start_date      DATE NOT NULL,
  end_date        DATE,
  is_active       BOOLEAN NOT NULL DEFAULT true,
  auto_deduct     BOOLEAN NOT NULL DEFAULT false,
  -- Lower = higher priority in deficit allocation.
  priority_level  INTEGER NOT NULL DEFAULT 50
                  CONSTRAINT valid_commitment_priority CHECK (priority_level BETWEEN 1 AND 100),
  created_by      UUID REFERENCES public.family_members(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT valid_date_range CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE TRIGGER trg_commitments_updated_at
  BEFORE UPDATE ON public.commitments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Per-cycle occurrence of a commitment (generated or manual).
-- ---------------------------------------------------------------------------

CREATE TABLE public.commitment_occurrences (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  commitment_id       UUID NOT NULL
                      REFERENCES public.commitments(id) ON DELETE CASCADE,
  family_id           UUID NOT NULL
                      REFERENCES public.family_groups(id) ON DELETE CASCADE,
  due_date            DATE NOT NULL,
  amount              NUMERIC(14,2) NOT NULL
                      CONSTRAINT positive_occurrence_amount CHECK (amount > 0),
  status              public.occurrence_status NOT NULL DEFAULT 'UPCOMING',
  -- Linked to the ledger when paid.
  paid_transaction_id UUID REFERENCES public.ledger_transactions(id) ON DELETE SET NULL,
  paid_at             TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.commitments IS 'Recurring or scheduled financial obligations (rent, school, subscriptions, etc.).';
COMMENT ON TABLE public.commitment_occurrences IS 'Individual due instances of a commitment within a financial cycle.';
