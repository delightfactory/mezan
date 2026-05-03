-- =============================================================================
-- Mezan: 00002_family_groups.sql
-- Top-level family entity. All financial data is scoped to a family.
-- =============================================================================

CREATE TABLE public.family_groups (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  currency    TEXT NOT NULL DEFAULT 'EGP'
              CONSTRAINT currency_iso CHECK (char_length(currency) = 3),
  -- Day of month when the financial cycle starts (salary day).
  -- Supports Egyptian patterns: 1, 15, 25, 28, etc.
  financial_cycle_day INTEGER NOT NULL DEFAULT 1
              CONSTRAINT valid_cycle_day CHECK (financial_cycle_day BETWEEN 1 AND 31),
  -- When true, recording income triggers automatic commitment allocation.
  auto_allocate_on_income BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Auto-update updated_at on modification.
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_family_groups_updated_at
  BEFORE UPDATE ON public.family_groups
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.family_groups IS 'Top-level family entity. All financial data is scoped by family_id.';
COMMENT ON COLUMN public.family_groups.financial_cycle_day IS 'Day of month the financial cycle starts (e.g. 25 for salary day).';
