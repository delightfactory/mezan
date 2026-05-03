-- =============================================================================
-- Mezan: 00006_ledger_transactions.sql
-- Immutable financial journal. Source of truth for all money movement.
-- =============================================================================

CREATE TABLE public.ledger_transactions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id       UUID NOT NULL
                  REFERENCES public.family_groups(id) ON DELETE RESTRICT,
  type            public.txn_type NOT NULL,
  status          public.txn_status NOT NULL DEFAULT 'POSTED',
  -- Amounts are always positive. Direction is determined by type + wallet fields.
  amount          NUMERIC(14,2) NOT NULL
                  CONSTRAINT positive_amount CHECK (amount > 0),
  from_wallet_id  UUID REFERENCES public.wallets(id) ON DELETE RESTRICT,
  to_wallet_id    UUID REFERENCES public.wallets(id) ON DELETE RESTRICT,
  category_id     UUID REFERENCES public.categories(id) ON DELETE RESTRICT,
  description     TEXT,
  -- When the transaction economically occurred.
  effective_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- When the record was created (audit timestamp).
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      UUID NOT NULL
                  REFERENCES public.family_members(id) ON DELETE RESTRICT,
  notes           TEXT,
  metadata        JSONB NOT NULL DEFAULT '{}',

  -- -----------------------------------------------------------------------
  -- Directional integrity constraints
  -- -----------------------------------------------------------------------
  -- INCOME must credit a wallet.
  CONSTRAINT income_needs_to_wallet CHECK (
    type != 'INCOME' OR to_wallet_id IS NOT NULL
  ),
  -- EXPENSE must debit a wallet.
  CONSTRAINT expense_needs_from_wallet CHECK (
    type != 'EXPENSE' OR from_wallet_id IS NOT NULL
  ),
  -- TRANSFER / ALLOCATION / DEALLOCATION need both wallets, and they must differ.
  CONSTRAINT transfer_needs_both_wallets CHECK (
    type NOT IN ('TRANSFER', 'ALLOCATION', 'DEALLOCATION')
    OR (from_wallet_id IS NOT NULL AND to_wallet_id IS NOT NULL AND from_wallet_id != to_wallet_id)
  ),
  -- OPENING_BALANCE credits a wallet.
  CONSTRAINT opening_balance_needs_to CHECK (
    type != 'OPENING_BALANCE' OR to_wallet_id IS NOT NULL
  ),
  -- REVERSAL inherits direction from original — just needs at least one wallet.
  CONSTRAINT reversal_has_wallet CHECK (
    type != 'REVERSAL' OR (from_wallet_id IS NOT NULL OR to_wallet_id IS NOT NULL)
  ),
  -- GAMEYA_INSTALLMENT is a transfer-like operation.
  CONSTRAINT gameya_installment_wallets CHECK (
    type != 'GAMEYA_INSTALLMENT'
    OR (from_wallet_id IS NOT NULL AND to_wallet_id IS NOT NULL AND from_wallet_id != to_wallet_id)
  ),
  CONSTRAINT gameya_payout_wallets CHECK (
    type != 'GAMEYA_PAYOUT'
    OR (from_wallet_id IS NOT NULL AND to_wallet_id IS NOT NULL AND from_wallet_id != to_wallet_id)
  ),
  -- LOAN_RECEIVE credits a wallet (money coming in).
  CONSTRAINT loan_receive_needs_to CHECK (
    type != 'LOAN_RECEIVE' OR to_wallet_id IS NOT NULL
  ),
  -- LOAN_DISBURSE debits a wallet (money going out to someone).
  CONSTRAINT loan_disburse_needs_from CHECK (
    type != 'LOAN_DISBURSE' OR from_wallet_id IS NOT NULL
  ),
  -- LOAN_PAYMENT_IN credits a wallet (someone paying us back).
  CONSTRAINT loan_payment_in_needs_to CHECK (
    type != 'LOAN_PAYMENT_IN' OR to_wallet_id IS NOT NULL
  ),
  -- LOAN_PAYMENT_OUT debits a wallet (we paying someone back).
  CONSTRAINT loan_payment_out_needs_from CHECK (
    type != 'LOAN_PAYMENT_OUT' OR from_wallet_id IS NOT NULL
  )
);

-- Prevent family deletion if ledger has records (RESTRICT above handles it).
COMMENT ON TABLE public.ledger_transactions IS 'Immutable financial ledger. No UPDATE on posted rows, no DELETE ever. Corrections via REVERSAL/ADJUSTMENT.';
COMMENT ON COLUMN public.ledger_transactions.amount IS 'Always positive. Direction determined by type + from/to wallet.';
COMMENT ON COLUMN public.ledger_transactions.effective_at IS 'Economic date of the transaction (may differ from created_at).';
