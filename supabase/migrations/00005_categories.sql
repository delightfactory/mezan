-- =============================================================================
-- Mezan: 00005_categories.sql
-- Hierarchical category tree for income, expense, and transfer classification.
-- =============================================================================

CREATE TABLE public.categories (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULL = system seed template; non-null = family-specific category.
  family_id     UUID REFERENCES public.family_groups(id) ON DELETE CASCADE,
  parent_id     UUID REFERENCES public.categories(id) ON DELETE SET NULL,
  name_ar       TEXT NOT NULL,
  name_en       TEXT,
  direction     public.category_direction NOT NULL,
  behavior      public.category_behavior NOT NULL DEFAULT 'VARIABLE_BUDGETED',
  -- Lower number = higher priority (used by deficit allocation engine).
  priority_level INTEGER NOT NULL DEFAULT 50
                CONSTRAINT valid_priority CHECK (priority_level BETWEEN 1 AND 100),
  is_system     BOOLEAN NOT NULL DEFAULT false,
  is_archived   BOOLEAN NOT NULL DEFAULT false,
  icon          TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.categories IS 'Hierarchical category tree. System templates have family_id IS NULL.';
COMMENT ON COLUMN public.categories.priority_level IS 'Lower = higher priority in deficit allocation. 1 = mandatory, 100 = discretionary.';
COMMENT ON COLUMN public.categories.behavior IS 'FIXED_ESSENTIAL, VARIABLE_BUDGETED, LUXURY, or SYSTEM (internal transfers).';
