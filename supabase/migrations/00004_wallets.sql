-- =============================================================================
-- Mezan: 00004_wallets.sql
-- Real and allocated wallets. Balance is cached, updated only via atomic RPCs.
-- =============================================================================

CREATE TABLE public.wallets (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id   UUID NOT NULL
              REFERENCES public.family_groups(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  type        public.wallet_type NOT NULL DEFAULT 'REAL',
  -- Cached derived value. Source of truth is the ledger.
  -- Updated ONLY inside atomic database functions with SELECT ... FOR UPDATE.
  balance     NUMERIC(14,2) NOT NULL DEFAULT 0,
  is_archived BOOLEAN NOT NULL DEFAULT false,
  icon        TEXT,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_by  UUID REFERENCES public.family_members(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Allocated wallets must not go negative.
  -- Real wallets may go negative temporarily within a locked RPC
  -- only if the system detects and blocks it before commit.
  CONSTRAINT wallet_non_negative
    CHECK (balance >= 0)
);

CREATE TRIGGER trg_wallets_updated_at
  BEFORE UPDATE ON public.wallets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.wallets IS 'Real (cash/bank) and allocated (reserve/fund) wallets. Balance is a cached value from the ledger.';
COMMENT ON COLUMN public.wallets.balance IS 'Cached balance. Only updated by atomic DB functions. Ledger is source of truth.';
