-- =============================================================================
-- Mezan: 00046_enforce_occurrence_for_scheduled_debts.sql
--
-- PURPOSE:
--   Adds a guard to fn_record_debt_payment and fn_record_payroll_deducted_income:
--   If a BORROWED_FROM debt has open debt_due_occurrences (UPCOMING / OVERDUE /
--   PARTIALLY_PAID) and p_debt_due_occurrence_id IS NULL, raise
--   DEBT_OCCURRENCE_REQUIRED so the caller cannot bypass the installment ledger.
--
--   This prevents remaining_amount drifting out of sync with the occurrence
--   totals, which would cause fn_calculate_safe_to_spend to double-count.
-- =============================================================================

-- ── fn_record_debt_payment (with DEBT_OCCURRENCE_REQUIRED guard) ──────────────
CREATE OR REPLACE FUNCTION public.fn_record_debt_payment(
  p_family_id              UUID,
  p_debt_id                UUID,
  p_amount                 NUMERIC(14,2),
  p_wallet_id              UUID,
  p_debt_due_occurrence_id UUID DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m            public.family_members;
  v_d            public.debts;
  v_w            public.wallets;
  v_occ          public.debt_due_occurrences;
  v_id           UUID;
  v_has_open_occ BOOLEAN;
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

  -- ── Guard: reject free-form payment for scheduled BORROWED_FROM debts ──────
  -- This is the primary protection against remaining_amount / occurrence drift.
  IF p_debt_due_occurrence_id IS NULL AND v_d.direction = 'BORROWED_FROM' THEN
    SELECT EXISTS(
      SELECT 1 FROM public.debt_due_occurrences
      WHERE debt_id = p_debt_id
        AND status IN ('UPCOMING', 'OVERDUE', 'PARTIALLY_PAID')
    ) INTO v_has_open_occ;

    IF v_has_open_occ THEN
      RAISE EXCEPTION 'DEBT_OCCURRENCE_REQUIRED';
    END IF;
  END IF;

  -- ── Validate provided occurrence ───────────────────────────────────────────
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
    IF v_occ.status NOT IN ('UPCOMING', 'OVERDUE', 'PARTIALLY_PAID') THEN
      RAISE EXCEPTION 'INVALID_DEBT_OCCURRENCE';
    END IF;
    IF p_amount > (v_occ.amount - v_occ.paid_amount) THEN
      RAISE EXCEPTION 'OCCURRENCE_OVERPAYMENT_NOT_ALLOWED';
    END IF;
  END IF;

  -- ── Ledger entry ───────────────────────────────────────────────────────────
  IF v_d.direction = 'BORROWED_FROM' THEN
    IF v_w.balance < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;
    INSERT INTO public.ledger_transactions(
      family_id, type, amount, from_wallet_id, description, created_by
    ) VALUES (
      p_family_id, 'LOAN_PAYMENT_OUT', p_amount, p_wallet_id,
      'سداد دين: ' || v_d.entity_name, v_m.id
    ) RETURNING id INTO v_id;
    UPDATE public.wallets SET balance = balance - p_amount WHERE id = p_wallet_id;
  ELSE
    INSERT INTO public.ledger_transactions(
      family_id, type, amount, to_wallet_id, description, created_by
    ) VALUES (
      p_family_id, 'LOAN_PAYMENT_IN', p_amount, p_wallet_id,
      'تحصيل دين: ' || v_d.entity_name, v_m.id
    ) RETURNING id INTO v_id;
    UPDATE public.wallets SET balance = balance + p_amount WHERE id = p_wallet_id;
  END IF;

  -- ── Update occurrence ──────────────────────────────────────────────────────
  IF p_debt_due_occurrence_id IS NOT NULL THEN
    IF (v_occ.paid_amount + p_amount) >= v_occ.amount THEN
      UPDATE public.debt_due_occurrences
      SET paid_amount = amount, status = 'PAID', updated_at = now()
      WHERE id = p_debt_due_occurrence_id;
      UPDATE public.debts
      SET installments_paid = installments_paid + 1
      WHERE id = p_debt_id;
    ELSE
      UPDATE public.debt_due_occurrences
      SET paid_amount = paid_amount + p_amount,
          status      = 'PARTIALLY_PAID',
          updated_at  = now()
      WHERE id = p_debt_due_occurrence_id;
    END IF;
  ELSE
    -- Legacy path: LENT_TO or FLEXIBLE debts with no scheduled occurrences
    IF v_d.payment_schedule_type = 'MONTHLY_INSTALLMENT'
       AND v_d.next_due_date IS NOT NULL THEN
      UPDATE public.debts
      SET next_due_date      = next_due_date + interval '1 month',
          installments_paid  = installments_paid + 1
      WHERE id = p_debt_id;
    END IF;
  END IF;

  -- ── Update debt remaining / settle ────────────────────────────────────────
  UPDATE public.debts
  SET remaining_amount = remaining_amount - p_amount,
      status = CASE
        WHEN remaining_amount - p_amount <= 0 THEN 'SETTLED'::public.debt_status
        ELSE status
      END
  WHERE id = p_debt_id;

  -- Cancel any remaining open occurrences on full settlement
  IF (v_d.remaining_amount - p_amount) <= 0 THEN
    UPDATE public.debt_due_occurrences
    SET status = 'CANCELLED', updated_at = now()
    WHERE debt_id = p_debt_id
      AND status IN ('UPCOMING', 'OVERDUE', 'PARTIALLY_PAID');
  END IF;

  -- ── Audit trail ───────────────────────────────────────────────────────────
  INSERT INTO public.debt_payments(
    debt_id, family_id, amount, transaction_id, debt_due_occurrence_id
  ) VALUES (p_debt_id, p_family_id, p_amount, v_id, p_debt_due_occurrence_id);

  INSERT INTO public.audit_events(
    family_id, action, actor_id, target_type, target_id, details
  ) VALUES (
    p_family_id, 'DEBT_PAYMENT', v_m.id, 'debt', p_debt_id,
    jsonb_build_object('amount', p_amount, 'occurrence_id', p_debt_due_occurrence_id)
  );

  INSERT INTO public.debt_events(
    family_id, debt_id, event_type, created_by, new_state
  ) VALUES (
    p_family_id, p_debt_id, 'PAYMENT_RECORDED', v_m.id,
    jsonb_build_object(
      'amount', p_amount, 'transaction_id', v_id,
      'occurrence_id', p_debt_due_occurrence_id
    )
  );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_record_debt_payment(UUID, UUID, NUMERIC, UUID, UUID)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.fn_record_debt_payment(UUID, UUID, NUMERIC, UUID, UUID)
  TO authenticated;


-- ── fn_record_payroll_deducted_income (with DEBT_OCCURRENCE_REQUIRED guard) ───
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
  v_m            public.family_members;
  v_w            public.wallets;
  v_d            public.debts;
  v_occ          public.debt_due_occurrences;
  v_in_tid       UUID;
  v_out_tid      UUID;
  v_has_open_occ BOOLEAN;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_total_income <= 0 OR p_deducted_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF p_deducted_amount > p_total_income THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;

  SELECT * INTO v_d FROM public.debts
  WHERE id = p_debt_id AND family_id = p_family_id AND status = 'ACTIVE'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DEBT_NOT_FOUND'; END IF;
  IF v_d.direction != 'BORROWED_FROM' THEN RAISE EXCEPTION 'INVALID_DEBT_DIRECTION'; END IF;
  IF p_deducted_amount > v_d.remaining_amount THEN RAISE EXCEPTION 'OVERPAYMENT'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.categories
    WHERE id = p_category_id
      AND direction = 'INCOME'
      AND (family_id IS NULL OR family_id = p_family_id)
      AND NOT is_archived
  ) THEN
    RAISE EXCEPTION 'INVALID_CATEGORY_DIRECTION';
  END IF;

  SELECT * INTO v_w FROM public.wallets
  WHERE id = p_wallet_id AND family_id = p_family_id AND NOT is_archived
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;

  -- ── Guard: reject free-form payroll deduction for scheduled debts ──────────
  IF p_debt_due_occurrence_id IS NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM public.debt_due_occurrences
      WHERE debt_id = p_debt_id
        AND status IN ('UPCOMING', 'OVERDUE', 'PARTIALLY_PAID')
    ) INTO v_has_open_occ;

    IF v_has_open_occ THEN
      RAISE EXCEPTION 'DEBT_OCCURRENCE_REQUIRED';
    END IF;
  END IF;

  -- ── Validate provided occurrence ───────────────────────────────────────────
  IF p_debt_due_occurrence_id IS NOT NULL THEN
    SELECT * INTO v_occ FROM public.debt_due_occurrences
    WHERE id = p_debt_due_occurrence_id
      AND debt_id = p_debt_id
      AND family_id = p_family_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_DEBT_OCCURRENCE'; END IF;
    IF v_occ.status NOT IN ('UPCOMING', 'OVERDUE', 'PARTIALLY_PAID') THEN
      RAISE EXCEPTION 'INVALID_DEBT_OCCURRENCE';
    END IF;
    IF p_deducted_amount > (v_occ.amount - v_occ.paid_amount) THEN
      RAISE EXCEPTION 'OCCURRENCE_OVERPAYMENT_NOT_ALLOWED';
    END IF;
  END IF;

  -- ── Ledger: credit income, then debit payment ─────────────────────────────
  INSERT INTO public.ledger_transactions(
    family_id, type, amount, to_wallet_id, category_id,
    description, effective_at, created_by
  ) VALUES (
    p_family_id, 'INCOME', p_total_income, p_wallet_id, p_category_id,
    COALESCE(p_description, 'راتب إجمالي (مخصوم منه دين)'), p_effective_at, v_m.id
  ) RETURNING id INTO v_in_tid;
  UPDATE public.wallets SET balance = balance + p_total_income WHERE id = p_wallet_id;

  INSERT INTO public.ledger_transactions(
    family_id, type, amount, from_wallet_id, description, effective_at, created_by
  ) VALUES (
    p_family_id, 'LOAN_PAYMENT_OUT', p_deducted_amount, p_wallet_id,
    'خصم سداد دين: ' || v_d.entity_name, p_effective_at, v_m.id
  ) RETURNING id INTO v_out_tid;
  UPDATE public.wallets SET balance = balance - p_deducted_amount WHERE id = p_wallet_id;

  -- ── Update occurrence ──────────────────────────────────────────────────────
  IF p_debt_due_occurrence_id IS NOT NULL THEN
    IF (v_occ.paid_amount + p_deducted_amount) >= v_occ.amount THEN
      UPDATE public.debt_due_occurrences
      SET paid_amount = amount, status = 'PAID', updated_at = now()
      WHERE id = p_debt_due_occurrence_id;
      UPDATE public.debts
      SET installments_paid = installments_paid + 1
      WHERE id = p_debt_id;
    ELSE
      UPDATE public.debt_due_occurrences
      SET paid_amount = paid_amount + p_deducted_amount,
          status      = 'PARTIALLY_PAID',
          updated_at  = now()
      WHERE id = p_debt_due_occurrence_id;
    END IF;
  END IF;

  -- ── Update debt remaining / settle ────────────────────────────────────────
  UPDATE public.debts
  SET remaining_amount = remaining_amount - p_deducted_amount,
      status = CASE
        WHEN remaining_amount - p_deducted_amount <= 0 THEN 'SETTLED'::public.debt_status
        ELSE status
      END
  WHERE id = p_debt_id;

  IF (v_d.remaining_amount - p_deducted_amount) <= 0 THEN
    UPDATE public.debt_due_occurrences
    SET status = 'CANCELLED', updated_at = now()
    WHERE debt_id = p_debt_id
      AND status IN ('UPCOMING', 'OVERDUE', 'PARTIALLY_PAID');
  END IF;

  -- ── Audit ─────────────────────────────────────────────────────────────────
  INSERT INTO public.debt_payments(
    debt_id, family_id, amount, transaction_id, debt_due_occurrence_id
  ) VALUES (p_debt_id, p_family_id, p_deducted_amount, v_out_tid, p_debt_due_occurrence_id);

  INSERT INTO public.audit_events(
    family_id, action, actor_id, target_type, target_id, details
  ) VALUES (
    p_family_id, 'PAYROLL_DEDUCTION', v_m.id, 'transaction', v_in_tid,
    jsonb_build_object(
      'income_txn_id', v_in_tid, 'payment_txn_id', v_out_tid,
      'debt_id', p_debt_id, 'deducted_amount', p_deducted_amount
    )
  );

  INSERT INTO public.debt_events(
    family_id, debt_id, event_type, created_by, new_state
  ) VALUES (
    p_family_id, p_debt_id, 'PAYMENT_RECORDED', v_m.id,
    jsonb_build_object(
      'amount', p_deducted_amount, 'transaction_id', v_out_tid,
      'payroll_income_txn', v_in_tid, 'occurrence_id', p_debt_due_occurrence_id
    )
  );

  RETURN QUERY SELECT v_in_tid, v_out_tid;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_record_payroll_deducted_income(
  UUID, NUMERIC, NUMERIC, UUID, UUID, UUID, TEXT, TIMESTAMPTZ, UUID
) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.fn_record_payroll_deducted_income(
  UUID, NUMERIC, NUMERIC, UUID, UUID, UUID, TEXT, TIMESTAMPTZ, UUID
) TO authenticated;
