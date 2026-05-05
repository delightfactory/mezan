-- =============================================================================
-- Mezan: 00038_partial_commitment_payments.sql
-- Partial Commitment Payments & Wallet Sorting Foundation
-- =============================================================================

-- 1. Add PARTIALLY_PAID status outside of transaction
ALTER TYPE public.occurrence_status ADD VALUE IF NOT EXISTS 'PARTIALLY_PAID';

BEGIN;

-- 2. Add paid_amount to commitment_occurrences
ALTER TABLE public.commitment_occurrences
  ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
  ADD CONSTRAINT chk_occurrence_paid_amount CHECK (paid_amount >= 0 AND paid_amount <= amount);

-- 3. Create commitment_payments table for partial payment history
CREATE TABLE IF NOT EXISTS public.commitment_payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  occurrence_id UUID NOT NULL REFERENCES public.commitment_occurrences(id) ON DELETE CASCADE,
  family_id UUID NOT NULL REFERENCES public.family_groups(id) ON DELETE CASCADE,
  amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  transaction_id UUID NOT NULL REFERENCES public.ledger_transactions(id) ON DELETE RESTRICT,
  paid_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID NOT NULL REFERENCES public.family_members(id) ON DELETE RESTRICT
);

-- RLS & Policies for commitment_payments
ALTER TABLE public.commitment_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY commitment_payments_select ON public.commitment_payments
  FOR SELECT TO authenticated
  USING (family_id IN (SELECT f.family_id FROM public.family_members f WHERE f.user_id = auth.uid()));

-- Insert/Update/Delete managed by RPCs only. No direct mutative policies.

-- 4. Update fn_pay_commitment_occurrence
CREATE OR REPLACE FUNCTION public.fn_pay_commitment_occurrence(
  p_family_id UUID,
  p_occurrence_id UUID,
  p_wallet_id UUID,
  p_amount NUMERIC(14,2) DEFAULT NULL,
  p_effective_at TIMESTAMPTZ DEFAULT now(),
  p_notes TEXT DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m public.family_members;
  v_occ public.commitment_occurrences;
  v_com public.commitments;
  v_w public.wallets;
  v_txn_id UUID;
  v_payment_id UUID;
  v_remaining NUMERIC(14,2);
  v_pay_amount NUMERIC(14,2);
BEGIN
  v_m := public._require_member(p_family_id);

  -- 1. Lock Occurrence
  SELECT * INTO v_occ FROM public.commitment_occurrences WHERE id = p_occurrence_id AND family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'COMMITMENT_NOT_FOUND'; END IF;
  IF v_occ.status NOT IN ('UPCOMING', 'OVERDUE', 'PARTIALLY_PAID') THEN RAISE EXCEPTION 'OCCURRENCE_NOT_PAYABLE'; END IF;

  v_remaining := v_occ.amount - v_occ.paid_amount;
  IF v_remaining <= 0 THEN RAISE EXCEPTION 'OCCURRENCE_ALREADY_PAID'; END IF;

  -- Determine amount to pay
  v_pay_amount := COALESCE(p_amount, v_remaining);
  IF v_pay_amount <= 0 THEN RAISE EXCEPTION 'INVALID_PAYMENT_AMOUNT'; END IF;
  IF v_pay_amount > v_remaining THEN RAISE EXCEPTION 'OVERPAYMENT_NOT_ALLOWED'; END IF;

  -- 2. Lock Commitment
  SELECT * INTO v_com FROM public.commitments WHERE id = v_occ.commitment_id AND family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'COMMITMENT_NOT_FOUND'; END IF;

  -- 3. Lock Wallet
  SELECT * INTO v_w FROM public.wallets WHERE id = p_wallet_id AND family_id = p_family_id AND NOT is_archived AND type = 'REAL' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  IF v_w.balance < v_pay_amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;

  -- 4. Record Expense Ledger Transaction
  INSERT INTO public.ledger_transactions (
    family_id, type, amount, from_wallet_id, category_id, description, effective_at, created_by, notes
  ) VALUES (
    p_family_id, 'EXPENSE', v_pay_amount, p_wallet_id, v_com.category_id, 'دفع التزام: ' || v_com.name, p_effective_at, v_m.id, p_notes
  ) RETURNING id INTO v_txn_id;

  -- 5. Record Commitment Payment
  INSERT INTO public.commitment_payments (
    occurrence_id, family_id, amount, transaction_id, paid_at, created_by
  ) VALUES (
    p_occurrence_id, p_family_id, v_pay_amount, v_txn_id, p_effective_at, v_m.id
  ) RETURNING id INTO v_payment_id;

  -- 6. Update Wallet
  UPDATE public.wallets SET balance = balance - v_pay_amount WHERE id = p_wallet_id;

  -- 7. Update Budget if exists
  UPDATE public.budgets
  SET spent_amount = spent_amount + v_pay_amount
  WHERE family_id = p_family_id
    AND category_id = v_com.category_id
    AND p_effective_at::date BETWEEN cycle_start AND cycle_end;

  -- 8. Mark Occurrence Paid/Partially Paid
  UPDATE public.commitment_occurrences
  SET 
    paid_amount = paid_amount + v_pay_amount,
    status = CASE WHEN paid_amount + v_pay_amount >= amount THEN 'PAID'::public.occurrence_status ELSE 'PARTIALLY_PAID'::public.occurrence_status END,
    paid_transaction_id = COALESCE(paid_transaction_id, v_txn_id), -- keep first for backward compat or last, keeping first is safer or just use last. We use last here for simplicity if user wants it, but user said "leave for old compat".
    paid_at = now()
  WHERE id = p_occurrence_id;

  -- 9. Audit
  INSERT INTO public.audit_events (family_id, action, actor_id, target_type, target_id, details)
  VALUES (p_family_id, 'COMMITMENT_PAID', v_m.id, 'commitment', v_com.id, jsonb_build_object(
    'occurrence_id', p_occurrence_id, 
    'payment_id', v_payment_id,
    'amount', v_pay_amount, 
    'transaction_id', v_txn_id,
    'is_partial', (v_pay_amount < v_remaining)
  ));

  RETURN v_txn_id;
END; $$;


-- 5. Fix Safe to Spend Calculation (Partial Payments)
CREATE OR REPLACE FUNCTION public.fn_calculate_safe_to_spend(p_family_id UUID)
RETURNS NUMERIC(14,2) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE 
  v_real NUMERIC(14,2); 
  v_alloc NUMERIC(14,2); 
  v_commits NUMERIC(14,2);
  v_debt_commits NUMERIC(14,2) := 0;
  v_cycle_end DATE;
  d RECORD;
BEGIN
  PERFORM public._require_member(p_family_id, ARRAY['OWNER','MEMBER','VIEWER']::public.member_role[]);
  
  SELECT COALESCE(SUM(balance),0) INTO v_real FROM public.wallets WHERE family_id=p_family_id AND type='REAL' AND NOT is_archived;
  SELECT COALESCE(SUM(balance),0) INTO v_alloc FROM public.wallets WHERE family_id=p_family_id AND type='ALLOCATED' AND NOT is_archived;
  
  -- Deduct only the remaining unpaid amount for commitments
  SELECT COALESCE(SUM(amount - paid_amount),0) INTO v_commits 
  FROM public.commitment_occurrences 
  WHERE family_id=p_family_id AND status IN ('UPCOMING','OVERDUE','PARTIALLY_PAID');
  
  -- Determine end of current cycle (end of current month for MVP)
  v_cycle_end := (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date;

  -- Calculate active debt obligations
  FOR d IN SELECT * FROM public.debts WHERE family_id = p_family_id AND direction = 'BORROWED_FROM' AND status = 'ACTIVE'
  LOOP
    IF d.payment_schedule_type = 'MONTHLY_INSTALLMENT' THEN
      IF d.next_due_date IS NOT NULL AND d.next_due_date <= v_cycle_end THEN
        v_debt_commits := v_debt_commits + LEAST(COALESCE(d.monthly_installment, d.remaining_amount), d.remaining_amount);
      END IF;
    ELSIF d.payment_schedule_type = 'ONE_TIME' THEN
      IF d.next_due_date IS NOT NULL AND d.next_due_date <= v_cycle_end THEN
        v_debt_commits := v_debt_commits + d.remaining_amount;
      END IF;
    ELSIF d.payment_schedule_type = 'FLEXIBLE' THEN
      IF d.next_due_date IS NOT NULL AND d.next_due_date <= v_cycle_end THEN
        v_debt_commits := v_debt_commits + LEAST(COALESCE(d.monthly_installment, d.remaining_amount), d.remaining_amount);
      END IF;
    END IF;
  END LOOP;

  RETURN GREATEST(v_real - v_alloc - v_commits - v_debt_commits, 0);
END; $$;

-- 6. Grants
REVOKE ALL ON FUNCTION public.fn_pay_commitment_occurrence(UUID, UUID, UUID, NUMERIC, TIMESTAMPTZ, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_pay_commitment_occurrence(UUID, UUID, UUID, NUMERIC, TIMESTAMPTZ, TEXT) TO authenticated;

COMMIT;
