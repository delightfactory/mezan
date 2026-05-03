-- =============================================================================
-- Mezan: 00012_budgets.sql
-- Per-category spending limits within a financial cycle.
-- =============================================================================

CREATE TABLE public.budgets (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id         UUID NOT NULL
                    REFERENCES public.family_groups(id) ON DELETE CASCADE,
  category_id       UUID NOT NULL
                    REFERENCES public.categories(id) ON DELETE RESTRICT,
  cycle_start       DATE NOT NULL,
  cycle_end         DATE NOT NULL,
  allocated_amount  NUMERIC(14,2) NOT NULL
                    CONSTRAINT positive_budget CHECK (allocated_amount > 0),
  -- Cached spent amount. Updated atomically by fn_record_expense.
  spent_amount      NUMERIC(14,2) NOT NULL DEFAULT 0
                    CONSTRAINT non_negative_spent CHECK (spent_amount >= 0),
  period            public.budget_period NOT NULL DEFAULT 'CYCLE',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT valid_budget_dates CHECK (cycle_end > cycle_start),
  CONSTRAINT uq_budget_family_cat_cycle UNIQUE (family_id, category_id, cycle_start)
);

CREATE TRIGGER trg_budgets_updated_at
  BEFORE UPDATE ON public.budgets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.budgets IS 'Per-category spending limits within a financial cycle. spent_amount is cached from the ledger.';
COMMENT ON COLUMN public.budgets.spent_amount IS 'Cached value. Updated atomically by expense recording RPC.';
