-- =============================================================================
-- Mezan: 00009_sinking_funds.sql
-- Pre-funded future expenses (school fees, Eid, emergency, clothing, etc.).
-- =============================================================================

CREATE TABLE public.sinking_funds (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id             UUID NOT NULL
                        REFERENCES public.family_groups(id) ON DELETE CASCADE,
  name                  TEXT NOT NULL,
  -- Each sinking fund is backed by an ALLOCATED wallet.
  wallet_id             UUID REFERENCES public.wallets(id) ON DELETE SET NULL,
  target_amount         NUMERIC(14,2) NOT NULL
                        CONSTRAINT positive_target CHECK (target_amount > 0),
  target_date           DATE,
  -- Suggested monthly contribution (configured, not auto-computed stored field).
  monthly_contribution  NUMERIC(14,2) NOT NULL DEFAULT 0
                        CONSTRAINT non_negative_contribution CHECK (monthly_contribution >= 0),
  is_active             BOOLEAN NOT NULL DEFAULT true,
  created_by            UUID REFERENCES public.family_members(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_sinking_funds_updated_at
  BEFORE UPDATE ON public.sinking_funds
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.sinking_funds IS 'Pre-funded goals: school fees, Eid, emergency, seasonal clothing, etc. Backed by an allocated wallet.';
COMMENT ON COLUMN public.sinking_funds.wallet_id IS 'The ALLOCATED wallet that holds accumulated funds for this goal.';
