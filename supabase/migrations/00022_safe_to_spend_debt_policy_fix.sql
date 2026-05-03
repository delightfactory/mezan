-- =============================================================================
-- Mezan: 00022_safe_to_spend_debt_policy_fix.sql
-- Safe-to-Spend Debt Deduction Policy Fix
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_calculate_safe_to_spend(p_family_id UUID)
RETURNS NUMERIC(14,2) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_real NUMERIC(14,2);
  v_commits NUMERIC(14,2);
  v_debts NUMERIC(14,2);
  v_gameya NUMERIC(14,2);
  v_end_of_month DATE;
BEGIN
  PERFORM public._require_member(p_family_id, ARRAY['OWNER','MEMBER','VIEWER']::public.member_role[]);
  
  -- Calculate end of current month (treating current month as the cycle)
  v_end_of_month := (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date;

  -- 1. Total active REAL wallet balances ONLY
  -- Do not subtract ALLOCATED wallet balances, as they are already physically held inside ALLOCATED wallets
  -- and deducting them again causes double deduction.
  SELECT COALESCE(SUM(balance),0) INTO v_real 
  FROM public.wallets 
  WHERE family_id = p_family_id AND type = 'REAL' AND NOT is_archived;

  -- 2. Unpaid due/upcoming commitments for current cycle
  SELECT COALESCE(SUM(amount),0) INTO v_commits 
  FROM public.commitment_occurrences 
  WHERE family_id = p_family_id 
    AND status IN ('UPCOMING','OVERDUE')
    AND due_date <= v_end_of_month;

  -- 3. Active debt installments due in current cycle (liability only)
  -- Policy: 
  -- IF monthly_installment > 0 THEN deduct LEAST(monthly_installment, remaining_amount)
  -- IF monthly_installment IS NULL AND due_date <= end_of_month THEN deduct remaining_amount
  -- ELSE 0 (do not deduct unscheduled or future debts)
  SELECT COALESCE(SUM(
    CASE
      WHEN monthly_installment IS NOT NULL AND monthly_installment > 0
        THEN LEAST(monthly_installment, remaining_amount)
      WHEN (monthly_installment IS NULL OR monthly_installment = 0)
        AND due_date IS NOT NULL
        AND due_date <= v_end_of_month
        THEN remaining_amount
      ELSE 0
    END
  ), 0) INTO v_debts
  FROM public.debts
  WHERE family_id = p_family_id
    AND status = 'ACTIVE'
    AND direction = 'BORROWED_FROM';

  -- 4. Upcoming gameya installments due in current cycle
  SELECT COALESCE(SUM(g.monthly_installment), 0) INTO v_gameya
  FROM public.gameya_turns t
  JOIN public.gameya_circles g ON t.gameya_id = g.id
  WHERE t.family_id = p_family_id
    AND t.status = 'UPCOMING'
    AND t.due_date <= v_end_of_month;

  RETURN GREATEST(v_real - v_commits - v_debts - v_gameya, 0);
END; $$;

REVOKE ALL ON FUNCTION public.fn_calculate_safe_to_spend(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_calculate_safe_to_spend(UUID) TO authenticated;
