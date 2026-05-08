-- =============================================================================
-- Mezan: 00045_borrowed_debt_obligations.sql
-- Borrowed Debt Obligations UX & Accounting Alignment
--
-- Goal:
--   Introduce debt_due_occurrences as the authoritative installment schedule
--   for BORROWED_FROM debts. Eliminates double-counting in Safe-to-Spend,
--   enables partial-payment tracking per installment, and supports Egyptian
--   loan scenarios (bank, employer advance, friend, store credit, card).
--
-- Key rules enforced here:
--   - Only BORROWED_FROM debts get occurrence rows.
--   - LENT_TO debts are out of scope for this phase.
--   - No commitment or commitment_occurrences rows are ever created for debts.
--   - All occurrence writes happen via RPC (no direct client INSERT/UPDATE).
--   - Safe-to-Spend reads from debt_due_occurrences for debts that have them,
--     and falls back to the legacy debts loop only for debts with no occurrences.
-- =============================================================================

BEGIN;

-- ===========================================================================
-- SECTION 1: Enum extension
-- ===========================================================================

-- PARTIALLY_PAID is used for both commitment_occurrences and debt_due_occurrences.
-- This avoids creating a separate enum for partial payments.
ALTER TYPE public.occurrence_status ADD VALUE IF NOT EXISTS 'PARTIALLY_PAID';

-- ===========================================================================
-- SECTION 2: debt_due_occurrences table
-- ===========================================================================

CREATE TABLE public.debt_due_occurrences (
  id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id     UUID          NOT NULL REFERENCES public.family_groups(id)  ON DELETE CASCADE,
  debt_id       UUID          NOT NULL REFERENCES public.debts(id)           ON DELETE CASCADE,
  due_date      DATE          NOT NULL,
  amount        NUMERIC(14,2) NOT NULL,
  paid_amount   NUMERIC(14,2) NOT NULL DEFAULT 0,
  status        public.occurrence_status NOT NULL DEFAULT 'UPCOMING',
  sequence_no   INT,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),

  CONSTRAINT ddo_amount_positive    CHECK (amount > 0),
  CONSTRAINT ddo_paid_non_negative  CHECK (paid_amount >= 0),
  CONSTRAINT ddo_paid_lte_amount    CHECK (paid_amount <= amount)
);

-- Updated-at trigger (reuses the project-wide helper set_updated_at())
CREATE TRIGGER trg_debt_due_occurrences_updated_at
  BEFORE UPDATE ON public.debt_due_occurrences
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Indexes
CREATE INDEX idx_debt_due_occurrences_family_due_status
  ON public.debt_due_occurrences (family_id, due_date, status);

CREATE INDEX idx_debt_due_occurrences_debt_due
  ON public.debt_due_occurrences (debt_id, due_date);

-- Unique sequence number per debt (only when sequence_no is set)
CREATE UNIQUE INDEX idx_debt_due_occurrences_seq_unique
  ON public.debt_due_occurrences (debt_id, sequence_no)
  WHERE sequence_no IS NOT NULL;

COMMENT ON TABLE public.debt_due_occurrences IS
  'Per-installment payment schedule for BORROWED_FROM debts. '
  'Source of truth for Safe-to-Spend deduction when occurrences exist. '
  'Never mix with commitment_occurrences — debts are never commitments.';

-- ===========================================================================
-- SECTION 3: Extend debt_payments with optional occurrence linkage
-- ===========================================================================

ALTER TABLE public.debt_payments
  ADD COLUMN IF NOT EXISTS debt_due_occurrence_id UUID
    REFERENCES public.debt_due_occurrences(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.debt_payments.debt_due_occurrence_id IS
  'Links this payment to a specific installment occurrence. NULL for free-form payments.';

-- ===========================================================================
-- SECTION 4: Row-Level Security for debt_due_occurrences
-- ===========================================================================
-- No direct client writes are allowed.
-- All writes happen through SECURITY DEFINER RPCs.

ALTER TABLE public.debt_due_occurrences ENABLE ROW LEVEL SECURITY;

-- SELECT: active family members only
CREATE POLICY ddo_select ON public.debt_due_occurrences
  FOR SELECT TO authenticated
  USING (family_id IN (SELECT public.get_my_family_ids()));

-- No INSERT / UPDATE / DELETE policies for clients.
-- Writes are handled exclusively by:
--   fn_receive_loan, fn_record_debt_payment,
--   fn_record_payroll_deducted_income, fn_reschedule_debt

COMMENT ON TABLE public.debt_due_occurrences IS
  'Per-installment payment schedule for BORROWED_FROM debts. '
  'RLS: read-only for authenticated family members. '
  'All writes via SECURITY DEFINER RPCs only.';

-- ===========================================================================
-- SECTION 5: Internal helper — _generate_debt_due_occurrences
-- ===========================================================================
-- SECURITY: intentionally NOT granted to authenticated/anon/public.
-- Called only from SECURITY DEFINER RPCs in this migration.

CREATE OR REPLACE FUNCTION public._generate_debt_due_occurrences(
  p_family_id            UUID,
  p_debt_id              UUID,
  p_original_amount      NUMERIC(14,2),
  p_payment_schedule_type public.payment_schedule_type,
  p_next_due_date        DATE,
  p_monthly_installment  NUMERIC(14,2),
  p_installment_count    INT,
  p_start_sequence       INT DEFAULT 1
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  i            INT;
  v_due        DATE;
  v_amount     NUMERIC(14,2);
  v_last_amt   NUMERIC(14,2);
BEGIN
  CASE p_payment_schedule_type

    WHEN 'FLEXIBLE' THEN
      -- No scheduled occurrences for flexible debts.
      RETURN;

    WHEN 'ONE_TIME' THEN
      IF p_next_due_date IS NULL THEN
        RAISE EXCEPTION 'NEXT_DUE_DATE_REQUIRED';
      END IF;
      INSERT INTO public.debt_due_occurrences
        (family_id, debt_id, due_date, amount, status, sequence_no)
      VALUES
        (p_family_id, p_debt_id, p_next_due_date, p_original_amount, 'UPCOMING', p_start_sequence);

    WHEN 'MONTHLY_INSTALLMENT' THEN
      IF p_next_due_date IS NULL THEN
        RAISE EXCEPTION 'NEXT_DUE_DATE_REQUIRED';
      END IF;
      IF COALESCE(p_monthly_installment, 0) <= 0 THEN
        RAISE EXCEPTION 'INVALID_INSTALLMENT_AMOUNT';
      END IF;
      IF COALESCE(p_installment_count, 0) <= 0 THEN
        RAISE EXCEPTION 'INSTALLMENT_COUNT_REQUIRED';
      END IF;
      -- Guard: if installment*(count-1) >= original_amount,
      -- the last installment would be zero or negative.
      IF p_monthly_installment * (p_installment_count - 1) >= p_original_amount THEN
        RAISE EXCEPTION 'INVALID_INSTALLMENT_PLAN';
      END IF;

      -- Generate N installments; last one absorbs any remainder.
      v_last_amt := p_original_amount - (p_monthly_installment * (p_installment_count - 1));

      FOR i IN 1..p_installment_count LOOP
        v_due    := p_next_due_date + ((i - 1) * interval '1 month');
        v_amount := CASE WHEN i < p_installment_count THEN p_monthly_installment ELSE v_last_amt END;

        INSERT INTO public.debt_due_occurrences
          (family_id, debt_id, due_date, amount, status, sequence_no)
        VALUES
          (p_family_id, p_debt_id, v_due, v_amount, 'UPCOMING', p_start_sequence + i - 1);
      END LOOP;

  END CASE;
END;
$$;

-- Explicitly revoke from all roles; only callable from SECURITY DEFINER RPCs.
REVOKE ALL ON FUNCTION public._generate_debt_due_occurrences(
  UUID, UUID, NUMERIC, public.payment_schedule_type, DATE, NUMERIC, INT, INT
) FROM PUBLIC, anon, authenticated;

-- ===========================================================================
-- SECTION 6: Updated fn_receive_loan
-- ===========================================================================
-- Adds occurrence generation after creating the debt.
-- Signature unchanged (backward-compatible defaults).

DROP FUNCTION IF EXISTS public.fn_receive_loan(
  UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ,
  public.debt_kind, public.payment_schedule_type,
  DATE, DATE, NUMERIC, INT, public.debt_priority_level, TEXT, TEXT
);

CREATE OR REPLACE FUNCTION public.fn_receive_loan(
  p_family_id            UUID,
  p_entity_name          TEXT,
  p_amount               NUMERIC(14,2),
  p_wallet_id            UUID,
  p_effective_at         TIMESTAMPTZ                  DEFAULT now(),
  p_debt_kind            public.debt_kind             DEFAULT 'PERSONAL',
  p_payment_schedule_type public.payment_schedule_type DEFAULT 'FLEXIBLE',
  p_start_date           DATE                         DEFAULT CURRENT_DATE,
  p_next_due_date        DATE                         DEFAULT NULL,
  p_monthly_installment  NUMERIC(14,2)               DEFAULT NULL,
  p_installment_count    INT                          DEFAULT NULL,
  p_priority_level       public.debt_priority_level   DEFAULT 'MEDIUM',
  p_counterparty_phone   TEXT                         DEFAULT NULL,
  p_counterparty_notes   TEXT                         DEFAULT NULL
)
RETURNS TABLE(debt_id UUID, transaction_id UUID)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m   public.family_members;
  v_w   public.wallets;
  v_did UUID;
  v_tid UUID;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;

  SELECT * INTO v_w
  FROM public.wallets
  WHERE id = p_wallet_id AND family_id = p_family_id AND NOT is_archived
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;

  -- Create the debt
  INSERT INTO public.debts(
    family_id, entity_name, direction, original_amount, remaining_amount,
    status, created_by, debt_kind, payment_schedule_type, start_date,
    next_due_date, monthly_installment, installment_count, priority_level,
    counterparty_phone, counterparty_notes
  ) VALUES (
    p_family_id, p_entity_name, 'BORROWED_FROM', p_amount, p_amount,
    'ACTIVE', v_m.id, p_debt_kind, p_payment_schedule_type, p_start_date,
    p_next_due_date, p_monthly_installment, p_installment_count, p_priority_level,
    p_counterparty_phone, p_counterparty_notes
  ) RETURNING id INTO v_did;

  -- Ledger + wallet
  INSERT INTO public.ledger_transactions(
    family_id, type, amount, to_wallet_id, description, effective_at, created_by
  ) VALUES (
    p_family_id, 'LOAN_RECEIVE', p_amount, p_wallet_id,
    'استدانة من: ' || p_entity_name, p_effective_at, v_m.id
  ) RETURNING id INTO v_tid;

  UPDATE public.wallets SET balance = balance + p_amount WHERE id = p_wallet_id;

  -- Audit + event
  INSERT INTO public.audit_events(family_id, action, actor_id, target_type, target_id, details)
  VALUES (p_family_id, 'DEBT_CREATED', v_m.id, 'debt', v_did,
    jsonb_build_object('type','BORROWED_FROM','amount',p_amount,'transaction_id',v_tid));

  INSERT INTO public.debt_events(family_id, debt_id, event_type, created_by, new_state)
  VALUES (p_family_id, v_did, 'CREATED', v_m.id,
    jsonb_build_object('amount',p_amount,'direction','BORROWED_FROM'));

  -- Generate installment occurrences (only for BORROWED_FROM — this function always is)
  PERFORM public._generate_debt_due_occurrences(
    p_family_id, v_did, p_amount, p_payment_schedule_type,
    p_next_due_date, p_monthly_installment, p_installment_count, 1
  );

  RETURN QUERY SELECT v_did, v_tid;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_receive_loan(
  UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ,
  public.debt_kind, public.payment_schedule_type,
  DATE, DATE, NUMERIC, INT, public.debt_priority_level, TEXT, TEXT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_receive_loan(
  UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ,
  public.debt_kind, public.payment_schedule_type,
  DATE, DATE, NUMERIC, INT, public.debt_priority_level, TEXT, TEXT
) TO authenticated;

-- ===========================================================================
-- SECTION 7: Updated fn_record_debt_payment
-- ===========================================================================
-- Adds p_debt_due_occurrence_id (optional) for occurrence-linked payments.

DROP FUNCTION IF EXISTS public.fn_record_debt_payment(UUID, UUID, NUMERIC, UUID);

CREATE OR REPLACE FUNCTION public.fn_record_debt_payment(
  p_family_id              UUID,
  p_debt_id                UUID,
  p_amount                 NUMERIC(14,2),
  p_wallet_id              UUID,
  p_debt_due_occurrence_id UUID DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m        public.family_members;
  v_d        public.debts;
  v_w        public.wallets;
  v_occ      public.debt_due_occurrences;
  v_id       UUID;
  v_has_occ  BOOLEAN;
  v_new_next DATE;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;

  SELECT * INTO v_d
  FROM public.debts
  WHERE id = p_debt_id AND family_id = p_family_id AND status = 'ACTIVE'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DEBT_NOT_FOUND'; END IF;

  IF p_amount > v_d.remaining_amount THEN RAISE EXCEPTION 'OVERPAYMENT'; END IF;

  SELECT * INTO v_w
  FROM public.wallets
  WHERE id = p_wallet_id AND family_id = p_family_id AND NOT is_archived
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;

  -- Occurrence validation (BORROWED_FROM only)
  IF p_debt_due_occurrence_id IS NOT NULL THEN
    IF v_d.direction != 'BORROWED_FROM' THEN
      RAISE EXCEPTION 'INVALID_DEBT_OCCURRENCE';
    END IF;
    SELECT * INTO v_occ
    FROM public.debt_due_occurrences
    WHERE id = p_debt_due_occurrence_id
      AND debt_id = p_debt_id
      AND family_id = p_family_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_DEBT_OCCURRENCE'; END IF;
    IF v_occ.status NOT IN ('UPCOMING','OVERDUE','PARTIALLY_PAID') THEN
      RAISE EXCEPTION 'INVALID_DEBT_OCCURRENCE';
    END IF;
    IF p_amount > (v_occ.amount - v_occ.paid_amount) THEN
      RAISE EXCEPTION 'OCCURRENCE_OVERPAYMENT_NOT_ALLOWED';
    END IF;
  END IF;

  -- Ledger + wallet movement
  IF v_d.direction = 'BORROWED_FROM' THEN
    IF v_w.balance < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;
    INSERT INTO public.ledger_transactions(family_id,type,amount,from_wallet_id,description,created_by)
    VALUES (p_family_id,'LOAN_PAYMENT_OUT',p_amount,p_wallet_id,'سداد دين: '||v_d.entity_name,v_m.id)
    RETURNING id INTO v_id;
    UPDATE public.wallets SET balance = balance - p_amount WHERE id = p_wallet_id;
  ELSE
    INSERT INTO public.ledger_transactions(family_id,type,amount,to_wallet_id,description,created_by)
    VALUES (p_family_id,'LOAN_PAYMENT_IN',p_amount,p_wallet_id,'تحصيل دين: '||v_d.entity_name,v_m.id)
    RETURNING id INTO v_id;
    UPDATE public.wallets SET balance = balance + p_amount WHERE id = p_wallet_id;
  END IF;

  -- Update occurrence if linked
  IF p_debt_due_occurrence_id IS NOT NULL THEN
    IF (v_occ.paid_amount + p_amount) >= v_occ.amount THEN
      -- Fully paid occurrence
      UPDATE public.debt_due_occurrences
      SET paid_amount = amount, status = 'PAID', updated_at = now()
      WHERE id = p_debt_due_occurrence_id;
      -- Increment installments_paid only on full completion
      UPDATE public.debts
      SET installments_paid = installments_paid + 1
      WHERE id = p_debt_id;
    ELSE
      -- Partial payment
      UPDATE public.debt_due_occurrences
      SET paid_amount = paid_amount + p_amount, status = 'PARTIALLY_PAID', updated_at = now()
      WHERE id = p_debt_due_occurrence_id;
      -- installments_paid unchanged
    END IF;
  ELSE
    -- Legacy free-form payment: advance next_due_date only if no occurrences exist
    SELECT EXISTS(
      SELECT 1 FROM public.debt_due_occurrences WHERE debt_id = p_debt_id
    ) INTO v_has_occ;

    IF NOT v_has_occ AND v_d.payment_schedule_type = 'MONTHLY_INSTALLMENT'
       AND v_d.next_due_date IS NOT NULL THEN
      v_new_next := v_d.next_due_date + interval '1 month';
      UPDATE public.debts SET next_due_date = v_new_next WHERE id = p_debt_id;
    END IF;

    -- For legacy mode, increment installments_paid on installment-type debts
    IF NOT v_has_occ AND v_d.payment_schedule_type = 'MONTHLY_INSTALLMENT' THEN
      UPDATE public.debts SET installments_paid = installments_paid + 1 WHERE id = p_debt_id;
    END IF;
  END IF;

  -- Reduce remaining and settle if zero
  UPDATE public.debts
  SET remaining_amount = remaining_amount - p_amount,
      status = CASE WHEN remaining_amount - p_amount <= 0 THEN 'SETTLED'::public.debt_status ELSE status END
  WHERE id = p_debt_id;

  -- Cancel remaining unpaid occurrences if debt is now settled
  IF (v_d.remaining_amount - p_amount) <= 0 THEN
    UPDATE public.debt_due_occurrences
    SET status = 'CANCELLED', updated_at = now()
    WHERE debt_id = p_debt_id
      AND status IN ('UPCOMING','OVERDUE','PARTIALLY_PAID');
  END IF;

  INSERT INTO public.debt_payments(debt_id, family_id, amount, transaction_id, debt_due_occurrence_id)
  VALUES (p_debt_id, p_family_id, p_amount, v_id, p_debt_due_occurrence_id);

  INSERT INTO public.audit_events(family_id, action, actor_id, target_type, target_id, details)
  VALUES (p_family_id,'DEBT_PAYMENT',v_m.id,'debt',p_debt_id,
    jsonb_build_object('amount',p_amount,'occurrence_id',p_debt_due_occurrence_id));

  INSERT INTO public.debt_events(family_id, debt_id, event_type, created_by, new_state)
  VALUES (p_family_id, p_debt_id, 'PAYMENT_RECORDED', v_m.id,
    jsonb_build_object('amount',p_amount,'transaction_id',v_id,
      'occurrence_id',p_debt_due_occurrence_id));

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_record_debt_payment(UUID,UUID,NUMERIC,UUID,UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.fn_record_debt_payment(UUID,UUID,NUMERIC,UUID,UUID) TO authenticated;

-- ===========================================================================
-- SECTION 8: Updated fn_record_payroll_deducted_income
-- ===========================================================================

DROP FUNCTION IF EXISTS public.fn_record_payroll_deducted_income(UUID,NUMERIC,NUMERIC,UUID,UUID,UUID,TEXT,TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION public.fn_record_payroll_deducted_income(
  p_family_id              UUID,
  p_total_income           NUMERIC(14,2),
  p_deducted_amount        NUMERIC(14,2),
  p_wallet_id              UUID,
  p_debt_id                UUID,
  p_category_id            UUID,
  p_description            TEXT        DEFAULT NULL,
  p_effective_at           TIMESTAMPTZ DEFAULT now(),
  p_debt_due_occurrence_id UUID        DEFAULT NULL
)
RETURNS TABLE(income_txn_id UUID, payment_txn_id UUID)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m      public.family_members;
  v_w      public.wallets;
  v_d      public.debts;
  v_occ    public.debt_due_occurrences;
  v_in_tid UUID;
  v_out_tid UUID;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_total_income <= 0 OR p_deducted_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF p_deducted_amount > p_total_income THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;

  SELECT * INTO v_d FROM public.debts
  WHERE id=p_debt_id AND family_id=p_family_id AND status='ACTIVE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DEBT_NOT_FOUND'; END IF;
  IF v_d.direction != 'BORROWED_FROM' THEN RAISE EXCEPTION 'INVALID_DEBT_DIRECTION'; END IF;
  IF p_deducted_amount > v_d.remaining_amount THEN RAISE EXCEPTION 'OVERPAYMENT'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.categories
    WHERE id=p_category_id AND direction='INCOME'
    AND (family_id IS NULL OR family_id=p_family_id) AND NOT is_archived) THEN
    RAISE EXCEPTION 'INVALID_CATEGORY_DIRECTION';
  END IF;

  SELECT * INTO v_w FROM public.wallets
  WHERE id=p_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;

  -- Validate occurrence if provided
  IF p_debt_due_occurrence_id IS NOT NULL THEN
    SELECT * INTO v_occ FROM public.debt_due_occurrences
    WHERE id=p_debt_due_occurrence_id AND debt_id=p_debt_id AND family_id=p_family_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_DEBT_OCCURRENCE'; END IF;
    IF v_occ.status NOT IN ('UPCOMING','OVERDUE','PARTIALLY_PAID') THEN
      RAISE EXCEPTION 'INVALID_DEBT_OCCURRENCE';
    END IF;
    IF p_deducted_amount > (v_occ.amount - v_occ.paid_amount) THEN
      RAISE EXCEPTION 'OCCURRENCE_OVERPAYMENT_NOT_ALLOWED';
    END IF;
  END IF;

  -- 1. Income
  INSERT INTO public.ledger_transactions(family_id,type,amount,to_wallet_id,category_id,description,effective_at,created_by)
  VALUES(p_family_id,'INCOME',p_total_income,p_wallet_id,p_category_id,
    COALESCE(p_description,'راتب إجمالي (مخصوم منه دين)'),p_effective_at,v_m.id)
  RETURNING id INTO v_in_tid;
  UPDATE public.wallets SET balance=balance+p_total_income WHERE id=p_wallet_id;

  -- 2. Debt payment
  INSERT INTO public.ledger_transactions(family_id,type,amount,from_wallet_id,description,effective_at,created_by)
  VALUES(p_family_id,'LOAN_PAYMENT_OUT',p_deducted_amount,p_wallet_id,
    'خصم سداد دين: '||v_d.entity_name,p_effective_at,v_m.id)
  RETURNING id INTO v_out_tid;
  UPDATE public.wallets SET balance=balance-p_deducted_amount WHERE id=p_wallet_id;

  -- 3. Update occurrence
  IF p_debt_due_occurrence_id IS NOT NULL THEN
    IF (v_occ.paid_amount + p_deducted_amount) >= v_occ.amount THEN
      UPDATE public.debt_due_occurrences SET paid_amount=amount, status='PAID', updated_at=now()
      WHERE id=p_debt_due_occurrence_id;
      UPDATE public.debts SET installments_paid=installments_paid+1 WHERE id=p_debt_id;
    ELSE
      UPDATE public.debt_due_occurrences
      SET paid_amount=paid_amount+p_deducted_amount, status='PARTIALLY_PAID', updated_at=now()
      WHERE id=p_debt_due_occurrence_id;
    END IF;
  END IF;

  -- 4. Reduce remaining
  UPDATE public.debts
  SET remaining_amount=remaining_amount-p_deducted_amount,
      status=CASE WHEN remaining_amount-p_deducted_amount<=0 THEN 'SETTLED'::public.debt_status ELSE status END
  WHERE id=p_debt_id;

  IF (v_d.remaining_amount - p_deducted_amount) <= 0 THEN
    UPDATE public.debt_due_occurrences SET status='CANCELLED', updated_at=now()
    WHERE debt_id=p_debt_id AND status IN ('UPCOMING','OVERDUE','PARTIALLY_PAID');
  END IF;

  INSERT INTO public.debt_payments(debt_id,family_id,amount,transaction_id,debt_due_occurrence_id)
  VALUES(p_debt_id,p_family_id,p_deducted_amount,v_out_tid,p_debt_due_occurrence_id);

  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details)
  VALUES(p_family_id,'PAYROLL_DEDUCTION',v_m.id,'transaction',v_in_tid,
    jsonb_build_object('income_txn_id',v_in_tid,'payment_txn_id',v_out_tid,
      'debt_id',p_debt_id,'deducted_amount',p_deducted_amount));

  INSERT INTO public.debt_events(family_id,debt_id,event_type,created_by,new_state)
  VALUES(p_family_id,p_debt_id,'PAYMENT_RECORDED',v_m.id,
    jsonb_build_object('amount',p_deducted_amount,'transaction_id',v_out_tid,
      'payroll_income_txn',v_in_tid,'occurrence_id',p_debt_due_occurrence_id));

  RETURN QUERY SELECT v_in_tid, v_out_tid;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_record_payroll_deducted_income(UUID,NUMERIC,NUMERIC,UUID,UUID,UUID,TEXT,TIMESTAMPTZ,UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.fn_record_payroll_deducted_income(UUID,NUMERIC,NUMERIC,UUID,UUID,UUID,TEXT,TIMESTAMPTZ,UUID) TO authenticated;

-- ===========================================================================
-- SECTION 9: Updated fn_reschedule_debt
-- ===========================================================================

DROP FUNCTION IF EXISTS public.fn_reschedule_debt(UUID,UUID,public.payment_schedule_type,DATE,NUMERIC,INT);

CREATE OR REPLACE FUNCTION public.fn_reschedule_debt(
  p_family_id             UUID,
  p_debt_id               UUID,
  p_payment_schedule_type public.payment_schedule_type,
  p_next_due_date         DATE            DEFAULT NULL,
  p_monthly_installment   NUMERIC(14,2)   DEFAULT NULL,
  p_installment_count     INT             DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m        public.family_members;
  v_d        public.debts;
  v_max_seq  INT;
BEGIN
  v_m := public._require_member(p_family_id, ARRAY['OWNER']::public.member_role[]);

  SELECT * INTO v_d FROM public.debts
  WHERE id=p_debt_id AND family_id=p_family_id AND status='ACTIVE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DEBT_NOT_FOUND'; END IF;

  IF p_payment_schedule_type = 'MONTHLY_INSTALLMENT' THEN
    IF COALESCE(p_monthly_installment,0) <= 0 THEN RAISE EXCEPTION 'INVALID_INSTALLMENT_AMOUNT'; END IF;
    IF p_next_due_date IS NULL THEN RAISE EXCEPTION 'NEXT_DUE_DATE_REQUIRED'; END IF;
    IF COALESCE(p_installment_count,0) <= 0 THEN RAISE EXCEPTION 'INSTALLMENT_COUNT_REQUIRED'; END IF;
  END IF;

  -- Guard: refuse if any occurrence is PARTIALLY_PAID
  IF EXISTS (
    SELECT 1 FROM public.debt_due_occurrences
    WHERE debt_id=p_debt_id AND status='PARTIALLY_PAID'
  ) THEN
    RAISE EXCEPTION 'HAS_PARTIAL_PAYMENTS_REQUIRES_MANUAL_HANDLING';
  END IF;

  -- Find the max sequence_no of PAID occurrences (to avoid unique index conflict)
  SELECT COALESCE(MAX(sequence_no),0) INTO v_max_seq
  FROM public.debt_due_occurrences
  WHERE debt_id=p_debt_id AND status='PAID';

  -- Remove only unpaid future occurrences
  DELETE FROM public.debt_due_occurrences
  WHERE debt_id=p_debt_id AND status IN ('UPCOMING','OVERDUE','CANCELLED');

  -- Update debt scheduling columns
  UPDATE public.debts SET
    payment_schedule_type=p_payment_schedule_type,
    next_due_date=p_next_due_date,
    monthly_installment=p_monthly_installment,
    installment_count=p_installment_count
  WHERE id=p_debt_id;

  -- Regenerate occurrences for the remaining amount
  IF p_payment_schedule_type != 'FLEXIBLE' THEN
    PERFORM public._generate_debt_due_occurrences(
      p_family_id, p_debt_id, v_d.remaining_amount,
      p_payment_schedule_type, p_next_due_date,
      p_monthly_installment, p_installment_count,
      v_max_seq + 1
    );
  END IF;

  INSERT INTO public.debt_events(family_id,debt_id,event_type,created_by,old_state,new_state)
  VALUES(p_family_id,p_debt_id,'RESCHEDULED',v_m.id,
    jsonb_build_object('payment_schedule_type',v_d.payment_schedule_type,
      'next_due_date',v_d.next_due_date,'monthly_installment',v_d.monthly_installment,
      'installment_count',v_d.installment_count),
    jsonb_build_object('payment_schedule_type',p_payment_schedule_type,
      'next_due_date',p_next_due_date,'monthly_installment',p_monthly_installment,
      'installment_count',p_installment_count));
END;
$$;

REVOKE ALL ON FUNCTION public.fn_reschedule_debt(UUID,UUID,public.payment_schedule_type,DATE,NUMERIC,INT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.fn_reschedule_debt(UUID,UUID,public.payment_schedule_type,DATE,NUMERIC,INT) TO authenticated;

-- ===========================================================================
-- SECTION 10: Updated fn_calculate_safe_to_spend
-- ===========================================================================
-- Rule: debt_due_occurrences for debts that have them;
--       legacy debts loop ONLY for debts with NO occurrences.

CREATE OR REPLACE FUNCTION public.fn_calculate_safe_to_spend(p_family_id UUID)
RETURNS NUMERIC(14,2) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_real         NUMERIC(14,2);
  v_alloc        NUMERIC(14,2);
  v_commits      NUMERIC(14,2);
  v_debt_occ     NUMERIC(14,2) := 0;
  v_debt_legacy  NUMERIC(14,2) := 0;
  v_gameya_flex  NUMERIC(14,2) := 0;
  v_gameya_leg   NUMERIC(14,2) := 0;
  v_cycle_end    DATE;
  d              RECORD;
BEGIN
  PERFORM public._require_member(p_family_id, ARRAY['OWNER','MEMBER','VIEWER']::public.member_role[]);

  v_cycle_end := (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date;

  SELECT COALESCE(SUM(balance),0) INTO v_real  FROM public.wallets WHERE family_id=p_family_id AND type='REAL'      AND NOT is_archived;
  SELECT COALESCE(SUM(balance),0) INTO v_alloc FROM public.wallets WHERE family_id=p_family_id AND type='ALLOCATED' AND NOT is_archived;

  -- 1. Regular commitments (amount - paid_amount)
  SELECT COALESCE(SUM(amount - paid_amount),0) INTO v_commits
  FROM public.commitment_occurrences
  WHERE family_id=p_family_id
    AND status IN ('UPCOMING','OVERDUE','PARTIALLY_PAID')
    AND due_date <= v_cycle_end;

  -- 2. Debt installments from debt_due_occurrences (BORROWED_FROM debts that have occurrences)
  SELECT COALESCE(SUM(ddo.amount - ddo.paid_amount), 0) INTO v_debt_occ
  FROM public.debt_due_occurrences ddo
  JOIN public.debts d2 ON d2.id = ddo.debt_id
  WHERE ddo.family_id = p_family_id
    AND d2.direction = 'BORROWED_FROM'
    AND d2.status    = 'ACTIVE'
    AND ddo.status  IN ('UPCOMING','OVERDUE','PARTIALLY_PAID')
    AND ddo.due_date <= v_cycle_end;

  -- 3. Legacy fallback: BORROWED_FROM debts with NO occurrence rows
  FOR d IN
    SELECT * FROM public.debts
    WHERE family_id=p_family_id AND direction='BORROWED_FROM' AND status='ACTIVE'
      AND NOT EXISTS (SELECT 1 FROM public.debt_due_occurrences WHERE debt_id=debts.id)
  LOOP
    IF d.payment_schedule_type = 'MONTHLY_INSTALLMENT' THEN
      IF d.next_due_date IS NOT NULL AND d.next_due_date <= v_cycle_end THEN
        v_debt_legacy := v_debt_legacy + LEAST(COALESCE(d.monthly_installment, d.remaining_amount), d.remaining_amount);
      END IF;
    ELSIF d.payment_schedule_type = 'ONE_TIME' THEN
      IF d.next_due_date IS NOT NULL AND d.next_due_date <= v_cycle_end THEN
        v_debt_legacy := v_debt_legacy + d.remaining_amount;
      END IF;
    ELSIF d.payment_schedule_type = 'FLEXIBLE' THEN
      IF d.next_due_date IS NOT NULL AND d.next_due_date <= v_cycle_end THEN
        v_debt_legacy := v_debt_legacy + LEAST(COALESCE(d.monthly_installment, d.remaining_amount), d.remaining_amount);
      END IF;
    END IF;
  END LOOP;

  -- 4. Gameya flex installments (unchanged)
  SELECT COALESCE(SUM(i.amount),0) INTO v_gameya_flex
  FROM public.gameya_installments i
  JOIN public.gameya_circles c ON c.id=i.gameya_id
  WHERE i.family_id=p_family_id
    AND i.status IN ('UPCOMING','OVERDUE')
    AND i.due_date <= v_cycle_end
    AND c.payout_debt_id IS NULL;

  -- 5. Gameya legacy turns fallback
  SELECT COALESCE(SUM(c.monthly_installment),0) INTO v_gameya_leg
  FROM public.gameya_turns t
  JOIN public.gameya_circles c ON t.gameya_id=c.id
  WHERE t.family_id=p_family_id
    AND t.status IN ('UPCOMING','MISSED')
    AND t.due_date <= v_cycle_end
    AND c.payout_debt_id IS NULL
    AND NOT EXISTS (SELECT 1 FROM public.gameya_installments i WHERE i.gameya_id=c.id);

  RETURN GREATEST(v_real - v_alloc - v_commits - v_debt_occ - v_debt_legacy - v_gameya_flex - v_gameya_leg, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_calculate_safe_to_spend(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.fn_calculate_safe_to_spend(UUID) TO authenticated;

COMMIT;
