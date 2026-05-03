-- =============================================================================
-- Mezan: 00010_debts.sql
-- Debts/loans tracking: borrowed-from and lent-to with payment history.
-- =============================================================================

CREATE TABLE public.debts (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id             UUID NOT NULL
                        REFERENCES public.family_groups(id) ON DELETE CASCADE,
  entity_name           TEXT NOT NULL,
  direction             public.debt_direction NOT NULL,
  original_amount       NUMERIC(14,2) NOT NULL
                        CONSTRAINT positive_original CHECK (original_amount > 0),
  remaining_amount      NUMERIC(14,2) NOT NULL
                        CONSTRAINT non_negative_remaining CHECK (remaining_amount >= 0),
  monthly_installment   NUMERIC(14,2)
                        CONSTRAINT non_negative_installment CHECK (
                          monthly_installment IS NULL OR monthly_installment >= 0
                        ),
  status                public.debt_status NOT NULL DEFAULT 'ACTIVE',
  notes                 TEXT,
  due_date              DATE,
  created_by            UUID REFERENCES public.family_members(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Remaining cannot exceed original.
  CONSTRAINT remaining_lte_original CHECK (remaining_amount <= original_amount)
);

CREATE TRIGGER trg_debts_updated_at
  BEFORE UPDATE ON public.debts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Individual debt payments, linked to ledger transactions.
-- ---------------------------------------------------------------------------

CREATE TABLE public.debt_payments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  debt_id         UUID NOT NULL
                  REFERENCES public.debts(id) ON DELETE RESTRICT,
  family_id       UUID NOT NULL
                  REFERENCES public.family_groups(id) ON DELETE CASCADE,
  amount          NUMERIC(14,2) NOT NULL
                  CONSTRAINT positive_payment CHECK (amount > 0),
  transaction_id  UUID REFERENCES public.ledger_transactions(id) ON DELETE RESTRICT,
  paid_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.debts IS 'Money owed to/from the family: BORROWED_FROM (liability) or LENT_TO (receivable).';
COMMENT ON TABLE public.debt_payments IS 'Individual payments against a debt, linked to the immutable ledger.';
