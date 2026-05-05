-- =============================================================================
-- Mezan: 00036_debt_expansion.sql
-- Debt and Loan Expansion (Phase 3)
-- =============================================================================

BEGIN;

-- 1. ENUMS
CREATE TYPE public.debt_kind AS ENUM ('PERSONAL', 'WORK_ADVANCE', 'INSTALLMENT', 'CARD', 'STORE_CREDIT', 'GAMEYA', 'OTHER');
CREATE TYPE public.payment_schedule_type AS ENUM ('ONE_TIME', 'MONTHLY_INSTALLMENT', 'FLEXIBLE');
CREATE TYPE public.debt_priority_level AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
CREATE TYPE public.debt_event_type AS ENUM ('CREATED', 'PAYMENT_RECORDED', 'METADATA_UPDATED', 'RESCHEDULED', 'WRITTEN_OFF');

-- Add WRITTEN_OFF to debt_status
ALTER TYPE public.debt_status ADD VALUE IF NOT EXISTS 'WRITTEN_OFF';

-- 2. Alter `debts`
ALTER TABLE public.debts
  ADD COLUMN debt_kind public.debt_kind NOT NULL DEFAULT 'PERSONAL',
  ADD COLUMN counterparty_phone TEXT,
  ADD COLUMN counterparty_notes TEXT,
  ADD COLUMN start_date DATE NOT NULL DEFAULT CURRENT_DATE,
  ADD COLUMN next_due_date DATE,
  ADD COLUMN installment_count INT,
  ADD COLUMN installments_paid INT NOT NULL DEFAULT 0,
  ADD COLUMN payment_schedule_type public.payment_schedule_type NOT NULL DEFAULT 'FLEXIBLE',
  ADD COLUMN priority_level public.debt_priority_level NOT NULL DEFAULT 'MEDIUM',
  ADD COLUMN is_payroll_deducted BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN source_reference_type TEXT,
  ADD COLUMN source_reference_id UUID,
  ADD COLUMN written_off_amount NUMERIC(14,2);

-- 3. Create `debt_events`
CREATE TABLE public.debt_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  debt_id UUID NOT NULL REFERENCES public.debts(id) ON DELETE CASCADE,
  family_id UUID NOT NULL REFERENCES public.family_groups(id) ON DELETE CASCADE,
  event_type public.debt_event_type NOT NULL,
  old_state JSONB,
  new_state JSONB,
  notes TEXT,
  created_by UUID REFERENCES public.family_members(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.debt_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Enable read access for family members" ON public.debt_events
  FOR SELECT TO authenticated
  USING (family_id IN (SELECT f FROM public.get_my_family_ids() f));

-- 4. Update Creation RPCs (Backwards Compatible)
DROP FUNCTION IF EXISTS public.fn_disburse_loan(UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION public.fn_disburse_loan(
  p_family_id UUID,
  p_entity_name TEXT,
  p_amount NUMERIC(14,2),
  p_wallet_id UUID,
  p_effective_at TIMESTAMPTZ DEFAULT now(),
  p_debt_kind public.debt_kind DEFAULT 'PERSONAL',
  p_payment_schedule_type public.payment_schedule_type DEFAULT 'FLEXIBLE',
  p_start_date DATE DEFAULT CURRENT_DATE,
  p_next_due_date DATE DEFAULT NULL,
  p_monthly_installment NUMERIC(14,2) DEFAULT NULL,
  p_installment_count INT DEFAULT NULL,
  p_priority_level public.debt_priority_level DEFAULT 'MEDIUM',
  p_counterparty_phone TEXT DEFAULT NULL,
  p_counterparty_notes TEXT DEFAULT NULL
)
RETURNS TABLE(debt_id UUID, transaction_id UUID) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_w public.wallets; v_did UUID; v_tid UUID;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  SELECT * INTO v_w FROM public.wallets WHERE id=p_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  IF v_w.balance < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;

  INSERT INTO public.debts(family_id, entity_name, direction, original_amount, remaining_amount, status, created_by, 
    debt_kind, payment_schedule_type, start_date, next_due_date, monthly_installment, installment_count, priority_level, counterparty_phone, counterparty_notes) 
  VALUES(p_family_id, p_entity_name, 'LENT_TO', p_amount, p_amount, 'ACTIVE', v_m.id,
    p_debt_kind, p_payment_schedule_type, p_start_date, p_next_due_date, p_monthly_installment, p_installment_count, p_priority_level, p_counterparty_phone, p_counterparty_notes) 
  RETURNING id INTO v_did;

  INSERT INTO public.ledger_transactions(family_id, type, amount, from_wallet_id, description, effective_at, created_by) 
  VALUES(p_family_id, 'LOAN_DISBURSE', p_amount, p_wallet_id, 'إقراض: '||p_entity_name, p_effective_at, v_m.id) RETURNING id INTO v_tid;
  
  UPDATE public.wallets SET balance=balance-p_amount WHERE id=p_wallet_id;
  
  INSERT INTO public.audit_events(family_id, action, actor_id, target_type, target_id, details) 
  VALUES(p_family_id, 'DEBT_CREATED', v_m.id, 'debt', v_did, jsonb_build_object('type', 'LENT_TO', 'amount', p_amount, 'transaction_id', v_tid));
  
  INSERT INTO public.debt_events(family_id, debt_id, event_type, created_by, new_state)
  VALUES(p_family_id, v_did, 'CREATED', v_m.id, jsonb_build_object('amount', p_amount, 'direction', 'LENT_TO'));

  RETURN QUERY SELECT v_did, v_tid;
END; $$;

DROP FUNCTION IF EXISTS public.fn_receive_loan(UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION public.fn_receive_loan(
  p_family_id UUID,
  p_entity_name TEXT,
  p_amount NUMERIC(14,2),
  p_wallet_id UUID,
  p_effective_at TIMESTAMPTZ DEFAULT now(),
  p_debt_kind public.debt_kind DEFAULT 'PERSONAL',
  p_payment_schedule_type public.payment_schedule_type DEFAULT 'FLEXIBLE',
  p_start_date DATE DEFAULT CURRENT_DATE,
  p_next_due_date DATE DEFAULT NULL,
  p_monthly_installment NUMERIC(14,2) DEFAULT NULL,
  p_installment_count INT DEFAULT NULL,
  p_priority_level public.debt_priority_level DEFAULT 'MEDIUM',
  p_counterparty_phone TEXT DEFAULT NULL,
  p_counterparty_notes TEXT DEFAULT NULL
)
RETURNS TABLE(debt_id UUID, transaction_id UUID) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_w public.wallets; v_did UUID; v_tid UUID;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  SELECT * INTO v_w FROM public.wallets WHERE id=p_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;

  INSERT INTO public.debts(family_id, entity_name, direction, original_amount, remaining_amount, status, created_by,
    debt_kind, payment_schedule_type, start_date, next_due_date, monthly_installment, installment_count, priority_level, counterparty_phone, counterparty_notes) 
  VALUES(p_family_id, p_entity_name, 'BORROWED_FROM', p_amount, p_amount, 'ACTIVE', v_m.id,
    p_debt_kind, p_payment_schedule_type, p_start_date, p_next_due_date, p_monthly_installment, p_installment_count, p_priority_level, p_counterparty_phone, p_counterparty_notes) 
  RETURNING id INTO v_did;

  INSERT INTO public.ledger_transactions(family_id, type, amount, to_wallet_id, description, effective_at, created_by) 
  VALUES(p_family_id, 'LOAN_RECEIVE', p_amount, p_wallet_id, 'استدانة من: '||p_entity_name, p_effective_at, v_m.id) RETURNING id INTO v_tid;
  
  UPDATE public.wallets SET balance=balance+p_amount WHERE id=p_wallet_id;
  
  INSERT INTO public.audit_events(family_id, action, actor_id, target_type, target_id, details) 
  VALUES(p_family_id, 'DEBT_CREATED', v_m.id, 'debt', v_did, jsonb_build_object('type', 'BORROWED_FROM', 'amount', p_amount, 'transaction_id', v_tid));
  
  INSERT INTO public.debt_events(family_id, debt_id, event_type, created_by, new_state)
  VALUES(p_family_id, v_did, 'CREATED', v_m.id, jsonb_build_object('amount', p_amount, 'direction', 'BORROWED_FROM'));

  RETURN QUERY SELECT v_did, v_tid;
END; $$;

-- 5. Update fn_record_debt_payment
CREATE OR REPLACE FUNCTION public.fn_record_debt_payment(
  p_family_id UUID, 
  p_debt_id UUID, 
  p_amount NUMERIC(14,2), 
  p_wallet_id UUID
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_d public.debts; v_w public.wallets; v_id UUID; v_new_next_due DATE;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  SELECT * INTO v_d FROM public.debts WHERE id=p_debt_id AND family_id=p_family_id AND status='ACTIVE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DEBT_NOT_FOUND'; END IF;
  IF p_amount > v_d.remaining_amount THEN RAISE EXCEPTION 'OVERPAYMENT'; END IF;
  SELECT * INTO v_w FROM public.wallets WHERE id=p_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  
  IF v_d.direction = 'BORROWED_FROM' THEN
    IF v_w.balance < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;
    INSERT INTO public.ledger_transactions(family_id,type,amount,from_wallet_id,description,created_by) VALUES(p_family_id,'LOAN_PAYMENT_OUT',p_amount,p_wallet_id,'سداد دين: '||v_d.entity_name,v_m.id) RETURNING id INTO v_id;
    UPDATE public.wallets SET balance=balance-p_amount WHERE id=p_wallet_id;
  ELSE
    INSERT INTO public.ledger_transactions(family_id,type,amount,to_wallet_id,description,created_by) VALUES(p_family_id,'LOAN_PAYMENT_IN',p_amount,p_wallet_id,'تحصيل دين: '||v_d.entity_name,v_m.id) RETURNING id INTO v_id;
    UPDATE public.wallets SET balance=balance+p_amount WHERE id=p_wallet_id;
  END IF;

  v_new_next_due := v_d.next_due_date;
  IF v_d.payment_schedule_type = 'MONTHLY_INSTALLMENT' AND v_d.next_due_date IS NOT NULL THEN
     v_new_next_due := v_d.next_due_date + interval '1 month';
  END IF;

  UPDATE public.debts 
  SET remaining_amount = remaining_amount - p_amount, 
      status = CASE WHEN remaining_amount - p_amount = 0 THEN 'SETTLED'::public.debt_status ELSE status END,
      installments_paid = installments_paid + CASE WHEN v_d.payment_schedule_type = 'MONTHLY_INSTALLMENT' THEN 1 ELSE 0 END,
      next_due_date = v_new_next_due
  WHERE id = p_debt_id;
  
  INSERT INTO public.debt_payments(debt_id,family_id,amount,transaction_id) VALUES(p_debt_id,p_family_id,p_amount,v_id);
  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) VALUES(p_family_id,'DEBT_PAYMENT',v_m.id,'debt',p_debt_id,jsonb_build_object('amount',p_amount));
  
  INSERT INTO public.debt_events(family_id, debt_id, event_type, created_by, new_state)
  VALUES(p_family_id, p_debt_id, 'PAYMENT_RECORDED', v_m.id, jsonb_build_object('amount', p_amount, 'transaction_id', v_id));

  RETURN v_id;
END; $$;

-- 6. New RPC: fn_update_debt_metadata (OWNER, MEMBER)
CREATE OR REPLACE FUNCTION public.fn_update_debt_metadata(
  p_family_id UUID,
  p_debt_id UUID,
  p_notes TEXT DEFAULT NULL,
  p_counterparty_phone TEXT DEFAULT NULL,
  p_counterparty_notes TEXT DEFAULT NULL,
  p_priority_level public.debt_priority_level DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_d public.debts;
BEGIN
  v_m := public._require_member(p_family_id, ARRAY['OWNER', 'MEMBER']::public.member_role[]);
  SELECT * INTO v_d FROM public.debts WHERE id=p_debt_id AND family_id=p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DEBT_NOT_FOUND'; END IF;

  UPDATE public.debts 
  SET 
    notes = COALESCE(p_notes, notes),
    counterparty_phone = COALESCE(p_counterparty_phone, counterparty_phone),
    counterparty_notes = COALESCE(p_counterparty_notes, counterparty_notes),
    priority_level = COALESCE(p_priority_level, priority_level)
  WHERE id = p_debt_id;

  INSERT INTO public.debt_events(family_id, debt_id, event_type, created_by, old_state, new_state)
  VALUES(
    p_family_id, p_debt_id, 'METADATA_UPDATED', v_m.id, 
    jsonb_build_object('notes', v_d.notes, 'counterparty_phone', v_d.counterparty_phone, 'priority_level', v_d.priority_level),
    jsonb_build_object('notes', p_notes, 'counterparty_phone', p_counterparty_phone, 'priority_level', p_priority_level)
  );
END; $$;

-- 7. New RPC: fn_reschedule_debt (OWNER)
CREATE OR REPLACE FUNCTION public.fn_reschedule_debt(
  p_family_id UUID,
  p_debt_id UUID,
  p_payment_schedule_type public.payment_schedule_type,
  p_next_due_date DATE DEFAULT NULL,
  p_monthly_installment NUMERIC(14,2) DEFAULT NULL,
  p_installment_count INT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_d public.debts;
BEGIN
  v_m := public._require_member(p_family_id, ARRAY['OWNER']::public.member_role[]);
  SELECT * INTO v_d FROM public.debts WHERE id=p_debt_id AND family_id=p_family_id AND status='ACTIVE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DEBT_NOT_FOUND'; END IF;

  IF p_payment_schedule_type = 'MONTHLY_INSTALLMENT' THEN
    IF COALESCE(p_monthly_installment, 0) <= 0 THEN RAISE EXCEPTION 'INVALID_INSTALLMENT_AMOUNT'; END IF;
    IF p_next_due_date IS NULL THEN RAISE EXCEPTION 'NEXT_DUE_DATE_REQUIRED'; END IF;
  END IF;

  IF p_installment_count IS NOT NULL AND p_installment_count < v_d.installments_paid THEN
    RAISE EXCEPTION 'INVALID_INSTALLMENT_COUNT: Cannot be less than already paid installments.';
  END IF;

  UPDATE public.debts 
  SET 
    payment_schedule_type = p_payment_schedule_type,
    next_due_date = p_next_due_date,
    monthly_installment = p_monthly_installment,
    installment_count = p_installment_count
  WHERE id = p_debt_id;

  INSERT INTO public.debt_events(family_id, debt_id, event_type, created_by, old_state, new_state)
  VALUES(
    p_family_id, p_debt_id, 'RESCHEDULED', v_m.id, 
    jsonb_build_object('payment_schedule_type', v_d.payment_schedule_type, 'next_due_date', v_d.next_due_date, 'monthly_installment', v_d.monthly_installment, 'installment_count', v_d.installment_count),
    jsonb_build_object('payment_schedule_type', p_payment_schedule_type, 'next_due_date', p_next_due_date, 'monthly_installment', p_monthly_installment, 'installment_count', p_installment_count)
  );
END; $$;

-- 8. New RPC: fn_write_off_debt (OWNER)
CREATE OR REPLACE FUNCTION public.fn_write_off_debt(
  p_family_id UUID,
  p_debt_id UUID,
  p_notes TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_d public.debts;
BEGIN
  v_m := public._require_member(p_family_id, ARRAY['OWNER']::public.member_role[]);
  SELECT * INTO v_d FROM public.debts WHERE id=p_debt_id AND family_id=p_family_id AND status='ACTIVE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DEBT_NOT_FOUND'; END IF;

  UPDATE public.debts 
  SET 
    status = 'WRITTEN_OFF',
    written_off_amount = remaining_amount,
    remaining_amount = 0
  WHERE id = p_debt_id;

  INSERT INTO public.debt_events(family_id, debt_id, event_type, created_by, notes, old_state, new_state)
  VALUES(
    p_family_id, p_debt_id, 'WRITTEN_OFF', v_m.id, p_notes,
    jsonb_build_object('remaining_amount', v_d.remaining_amount, 'status', v_d.status),
    jsonb_build_object('remaining_amount', 0, 'status', 'WRITTEN_OFF', 'written_off_amount', v_d.remaining_amount)
  );

  INSERT INTO public.audit_events(family_id, action, actor_id, target_type, target_id, details) 
  VALUES(p_family_id, 'DEBT_WRITTEN_OFF', v_m.id, 'debt', p_debt_id, jsonb_build_object('written_off_amount', v_d.remaining_amount, 'notes', p_notes));

END; $$;

-- 9. New RPC: fn_record_payroll_deducted_income (OWNER, MEMBER)
CREATE OR REPLACE FUNCTION public.fn_record_payroll_deducted_income(
  p_family_id UUID,
  p_total_income NUMERIC(14,2),
  p_deducted_amount NUMERIC(14,2),
  p_wallet_id UUID,
  p_debt_id UUID,
  p_category_id UUID,
  p_description TEXT DEFAULT NULL,
  p_effective_at TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE(income_txn_id UUID, payment_txn_id UUID) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_w public.wallets; v_d public.debts; v_in_tid UUID; v_out_tid UUID; v_new_next_due DATE;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_total_income <= 0 OR p_deducted_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF p_deducted_amount > p_total_income THEN RAISE EXCEPTION 'INVALID_AMOUNT: Deduction cannot exceed total income.'; END IF;

  SELECT * INTO v_d FROM public.debts WHERE id=p_debt_id AND family_id=p_family_id AND status='ACTIVE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DEBT_NOT_FOUND'; END IF;
  IF v_d.direction != 'BORROWED_FROM' THEN RAISE EXCEPTION 'INVALID_DEBT_DIRECTION: Must be a BORROWED_FROM debt.'; END IF;
  IF p_deducted_amount > v_d.remaining_amount THEN RAISE EXCEPTION 'OVERPAYMENT'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.categories WHERE id = p_category_id AND direction = 'INCOME' AND (family_id IS NULL OR family_id = p_family_id) AND NOT is_archived) THEN
    RAISE EXCEPTION 'INVALID_CATEGORY_DIRECTION';
  END IF;

  SELECT * INTO v_w FROM public.wallets WHERE id=p_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;

  -- 1. Record Income into Wallet (Full amount)
  INSERT INTO public.ledger_transactions(family_id, type, amount, to_wallet_id, category_id, description, effective_at, created_by) 
  VALUES(p_family_id, 'INCOME', p_total_income, p_wallet_id, p_category_id, COALESCE(p_description, 'راتب إجمالي (مخصوم منه دين)'), p_effective_at, v_m.id) RETURNING id INTO v_in_tid;
  
  -- 2. Update Wallet with Full amount first
  UPDATE public.wallets SET balance=balance+p_total_income WHERE id=p_wallet_id;

  -- 3. Record Debt Payment from Wallet
  -- Wallet now has the income, so we can deduct safely
  INSERT INTO public.ledger_transactions(family_id, type, amount, from_wallet_id, description, effective_at, created_by) 
  VALUES(p_family_id, 'LOAN_PAYMENT_OUT', p_deducted_amount, p_wallet_id, 'خصم سداد دين: '||v_d.entity_name, p_effective_at, v_m.id) RETURNING id INTO v_out_tid;
  
  UPDATE public.wallets SET balance=balance-p_deducted_amount WHERE id=p_wallet_id;

  -- 4. Update Debt
  v_new_next_due := v_d.next_due_date;
  IF v_d.payment_schedule_type = 'MONTHLY_INSTALLMENT' AND v_d.next_due_date IS NOT NULL THEN
     v_new_next_due := v_d.next_due_date + interval '1 month';
  END IF;

  UPDATE public.debts 
  SET remaining_amount = remaining_amount - p_deducted_amount, 
      status = CASE WHEN remaining_amount - p_deducted_amount = 0 THEN 'SETTLED'::public.debt_status ELSE status END,
      installments_paid = installments_paid + CASE WHEN v_d.payment_schedule_type = 'MONTHLY_INSTALLMENT' THEN 1 ELSE 0 END,
      next_due_date = v_new_next_due
  WHERE id = p_debt_id;

  INSERT INTO public.debt_payments(debt_id,family_id,amount,transaction_id) VALUES(p_debt_id,p_family_id,p_deducted_amount,v_out_tid);
  
  -- 5. Link the transactions in Audit & Debt Events
  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) 
  VALUES(p_family_id,'PAYROLL_DEDUCTION',v_m.id,'transaction',v_in_tid,jsonb_build_object('income_txn_id', v_in_tid, 'payment_txn_id', v_out_tid, 'debt_id', p_debt_id, 'deducted_amount', p_deducted_amount));
  
  INSERT INTO public.debt_events(family_id, debt_id, event_type, created_by, new_state)
  VALUES(p_family_id, p_debt_id, 'PAYMENT_RECORDED', v_m.id, jsonb_build_object('amount', p_deducted_amount, 'transaction_id', v_out_tid, 'payroll_income_txn', v_in_tid));

  RETURN QUERY SELECT v_in_tid, v_out_tid;
END; $$;

-- Grants
REVOKE ALL ON FUNCTION public.fn_disburse_loan(UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ, public.debt_kind, public.payment_schedule_type, DATE, DATE, NUMERIC, INT, public.debt_priority_level, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_disburse_loan(UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ, public.debt_kind, public.payment_schedule_type, DATE, DATE, NUMERIC, INT, public.debt_priority_level, TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_receive_loan(UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ, public.debt_kind, public.payment_schedule_type, DATE, DATE, NUMERIC, INT, public.debt_priority_level, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_receive_loan(UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ, public.debt_kind, public.payment_schedule_type, DATE, DATE, NUMERIC, INT, public.debt_priority_level, TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_update_debt_metadata(UUID, UUID, TEXT, TEXT, TEXT, public.debt_priority_level) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_update_debt_metadata(UUID, UUID, TEXT, TEXT, TEXT, public.debt_priority_level) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_reschedule_debt(UUID, UUID, public.payment_schedule_type, DATE, NUMERIC, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_reschedule_debt(UUID, UUID, public.payment_schedule_type, DATE, NUMERIC, INT) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_write_off_debt(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_write_off_debt(UUID, UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_record_payroll_deducted_income(UUID, NUMERIC, NUMERIC, UUID, UUID, UUID, TEXT, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_record_payroll_deducted_income(UUID, NUMERIC, NUMERIC, UUID, UUID, UUID, TEXT, TIMESTAMPTZ) TO authenticated;

COMMIT;
