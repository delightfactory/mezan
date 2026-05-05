-- =============================================================================
-- Mezan: 00037_debt_expansion_hardening.sql
-- Debt Expansion Hardening (Blockers Resolution)
-- =============================================================================

BEGIN;

-- 1. Add missing audit_action values
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'DEBT_WRITTEN_OFF';
ALTER TYPE public.audit_action ADD VALUE IF NOT EXISTS 'PAYROLL_DEDUCTION';

-- 2. Drop direct insertion/update on debts to enforce RPC usage
DROP POLICY IF EXISTS debts_insert ON public.debts;
DROP POLICY IF EXISTS debts_update ON public.debts;

-- Ensure read access remains
-- (debts_select already exists)

-- 3. Overhaul fn_calculate_safe_to_spend to include active debt obligations
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
  SELECT COALESCE(SUM(amount),0) INTO v_commits FROM public.commitment_occurrences WHERE family_id=p_family_id AND status IN ('UPCOMING','OVERDUE');
  
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

COMMIT;
