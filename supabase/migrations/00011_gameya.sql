-- =============================================================================
-- Mezan: 00011_gameya.sql
-- Egyptian Gam'eya (savings circle) — asset before payout, liability after.
-- =============================================================================

CREATE TABLE public.gameya_circles (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id             UUID NOT NULL
                        REFERENCES public.family_groups(id) ON DELETE CASCADE,
  name                  TEXT NOT NULL,
  monthly_installment   NUMERIC(14,2) NOT NULL
                        CONSTRAINT positive_installment CHECK (monthly_installment > 0),
  total_months          INTEGER NOT NULL
                        CONSTRAINT positive_months CHECK (total_months > 0),
  -- Which month (1-based) the family receives the payout.
  payout_month          INTEGER NOT NULL,
  status                public.gameya_status NOT NULL DEFAULT 'SAVING_PHASE',
  start_date            DATE NOT NULL,
  -- The ALLOCATED wallet that accumulates installment payments before payout.
  wallet_id             UUID REFERENCES public.wallets(id) ON DELETE SET NULL,
  -- Computed payout amount: installment × total months.
  payout_amount         NUMERIC(14,2) GENERATED ALWAYS AS (
                          monthly_installment * total_months
                        ) STORED,
  created_by            UUID REFERENCES public.family_members(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT valid_payout_month CHECK (payout_month BETWEEN 1 AND total_months)
);

CREATE TRIGGER trg_gameya_circles_updated_at
  BEFORE UPDATE ON public.gameya_circles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Individual turns (months) of the gam'eya.
-- ---------------------------------------------------------------------------

CREATE TABLE public.gameya_turns (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gameya_id       UUID NOT NULL
                  REFERENCES public.gameya_circles(id) ON DELETE CASCADE,
  family_id       UUID NOT NULL
                  REFERENCES public.family_groups(id) ON DELETE CASCADE,
  turn_number     INTEGER NOT NULL
                  CONSTRAINT positive_turn CHECK (turn_number > 0),
  due_date        DATE NOT NULL,
  status          public.gameya_turn_status NOT NULL DEFAULT 'UPCOMING',
  transaction_id  UUID REFERENCES public.ledger_transactions(id) ON DELETE SET NULL,
  paid_at         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT uq_gameya_turn UNIQUE (gameya_id, turn_number)
);

COMMENT ON TABLE public.gameya_circles IS 'Egyptian savings circle. Asset before payout month, liability after early payout.';
COMMENT ON COLUMN public.gameya_circles.payout_month IS '1-based month number when the family receives the full payout.';
COMMENT ON COLUMN public.gameya_circles.payout_amount IS 'Generated: monthly_installment × total_months.';
COMMENT ON TABLE public.gameya_turns IS 'Individual monthly turns of a gam''eya. Tracks payment status per month.';
