-- =============================================================================
-- Mezan: 00039_phase4a_hardening.sql
-- Phase 4A Hardening: Clean Overloads, Fix RLS, Restore Gameya Safe-To-Spend
-- =============================================================================

BEGIN;

-- 1. Remove the old function overload for fn_pay_commitment_occurrence
DROP FUNCTION IF EXISTS public.fn_pay_commitment_occurrence(UUID, UUID, UUID, TIMESTAMPTZ, TEXT);

-- (The new overload fn_pay_commitment_occurrence(UUID, UUID, UUID, NUMERIC, TIMESTAMPTZ, TEXT) remains intact from 00038)


-- 2. Fix RLS policy on commitment_payments to use get_my_family_ids()
DROP POLICY IF EXISTS commitment_payments_select ON public.commitment_payments;
CREATE POLICY commitment_payments_select ON public.commitment_payments
  FOR SELECT TO authenticated
  USING (family_id IN (SELECT public.get_my_family_ids()));


-- 3. Change commitment_payments default ID to gen_random_uuid()
ALTER TABLE public.commitment_payments ALTER COLUMN id SET DEFAULT gen_random_uuid();


-- 4. Redefine fn_calculate_safe_to_spend to correctly include Gameya installments
CREATE OR REPLACE FUNCTION public.fn_calculate_safe_to_spend(p_family_id UUID)
RETURNS NUMERIC(14,2) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE 
  v_real NUMERIC(14,2); 
  v_alloc NUMERIC(14,2); 
  v_commits NUMERIC(14,2);
  v_debt_commits NUMERIC(14,2) := 0;
  v_gameya_flex NUMERIC(14,2) := 0;
  v_gameya_legacy NUMERIC(14,2) := 0;
  v_cycle_end DATE;
  d RECORD;
BEGIN
  PERFORM public._require_member(p_family_id, ARRAY['OWNER','MEMBER','VIEWER']::public.member_role[]);
  
  -- Determine end of current cycle (end of current month for MVP)
  v_cycle_end := (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date;

  SELECT COALESCE(SUM(balance),0) INTO v_real FROM public.wallets WHERE family_id=p_family_id AND type='REAL' AND NOT is_archived;
  SELECT COALESCE(SUM(balance),0) INTO v_alloc FROM public.wallets WHERE family_id=p_family_id AND type='ALLOCATED' AND NOT is_archived;
  
  -- 1. Deduct only the remaining unpaid amount for commitments
  SELECT COALESCE(SUM(amount - paid_amount),0) INTO v_commits 
  FROM public.commitment_occurrences 
  WHERE family_id=p_family_id AND status IN ('UPCOMING','OVERDUE','PARTIALLY_PAID')
    AND due_date <= v_cycle_end;
  
  -- 2. Calculate active debt obligations (00037 logic)
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

  -- 3. Upcoming gameya installments due in current cycle
  SELECT COALESCE(SUM(i.amount), 0) INTO v_gameya_flex
  FROM public.gameya_installments i
  JOIN public.gameya_circles c ON c.id = i.gameya_id
  WHERE i.family_id = p_family_id
    AND i.status IN ('UPCOMING', 'OVERDUE')
    AND i.due_date <= v_cycle_end
    AND c.payout_debt_id IS NULL; -- Prevent double-count if debt is active

  -- 4. Upcoming gameya turns due in current cycle (Legacy Logic fallback)
  SELECT COALESCE(SUM(c.monthly_installment), 0) INTO v_gameya_legacy
  FROM public.gameya_turns t
  JOIN public.gameya_circles c ON t.gameya_id = c.id
  WHERE t.family_id = p_family_id
    AND t.status IN ('UPCOMING', 'MISSED')
    AND t.due_date <= v_cycle_end
    AND c.payout_debt_id IS NULL -- Prevent double-count if debt is active
    AND NOT EXISTS (
      SELECT 1 FROM public.gameya_installments i WHERE i.gameya_id = c.id
    );

  RETURN GREATEST(v_real - v_alloc - v_commits - v_debt_commits - v_gameya_flex - v_gameya_legacy, 0);
END; $$;

-- Re-grant execute on fn_calculate_safe_to_spend just in case
REVOKE ALL ON FUNCTION public.fn_calculate_safe_to_spend(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_calculate_safe_to_spend(UUID) TO authenticated;

COMMIT;
