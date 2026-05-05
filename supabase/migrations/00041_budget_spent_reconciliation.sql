-- =============================================================================
-- Mezan: 00041_budget_spent_reconciliation.sql
-- Description: Adds RPC to recalculate budget spent amount from ledger_transactions
-- and performs a one-time backfill/reconciliation of existing budgets.
-- =============================================================================

-- 1. Create RPC to recalculate budget spent amount safely
CREATE OR REPLACE FUNCTION public.fn_recalculate_budget_spent(p_budget_id UUID)
RETURNS NUMERIC(14,2) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_budget public.budgets;
  v_m public.family_members;
  v_new_spent NUMERIC(14,2);
BEGIN
  -- Lock the budget row
  SELECT * INTO v_budget FROM public.budgets WHERE id = p_budget_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BUDGET_NOT_FOUND'; END IF;

  -- Verify user is a member of the family
  v_m := public._require_member(v_budget.family_id);

  -- Calculate true spent from ledger_transactions
  SELECT COALESCE(SUM(amount), 0) INTO v_new_spent
  FROM public.ledger_transactions
  WHERE family_id = v_budget.family_id
    AND category_id = v_budget.category_id
    AND type = 'EXPENSE'
    AND status = 'POSTED'
    AND effective_at >= v_budget.cycle_start::timestamptz
    AND effective_at < (v_budget.cycle_end + interval '1 day')::timestamptz;

  -- Update the budget
  UPDATE public.budgets
  SET spent_amount = v_new_spent
  WHERE id = p_budget_id;

  RETURN v_new_spent;
END; $$;

-- Revoke from public, grant to authenticated
REVOKE ALL ON FUNCTION public.fn_recalculate_budget_spent(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_recalculate_budget_spent(UUID) TO authenticated;


-- 2. One-time reconciliation of all existing budgets
-- This query uses a subselect to sum the exact POSTED EXPENSE transactions
-- matching the budget's family, category, and cycle bounds.
UPDATE public.budgets b
SET spent_amount = COALESCE((
  SELECT SUM(lt.amount)
  FROM public.ledger_transactions lt
  WHERE lt.family_id = b.family_id
    AND lt.category_id = b.category_id
    AND lt.type = 'EXPENSE'
    AND lt.status = 'POSTED'
    AND lt.effective_at >= b.cycle_start::timestamptz
    AND lt.effective_at < (b.cycle_end + interval '1 day')::timestamptz
), 0);
