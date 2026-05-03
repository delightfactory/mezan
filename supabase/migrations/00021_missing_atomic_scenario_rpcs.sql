-- =============================================================================
-- Mezan: 00021_missing_atomic_scenario_rpcs.sql
-- Missing Atomic RPCs for Egyptian Scenarios (Gameya, Budget, Commitments)
-- =============================================================================

-- =============================================================================
-- 1. Create Gameya Circle
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_create_gameya_circle(
  p_family_id UUID,
  p_name TEXT,
  p_monthly_installment NUMERIC(14,2),
  p_total_months INTEGER,
  p_payout_month INTEGER,
  p_start_date DATE
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m public.family_members;
  v_wallet_id UUID;
  v_gameya_id UUID;
  v_i INTEGER;
BEGIN
  v_m := public._require_member(p_family_id);

  IF p_monthly_installment <= 0 THEN RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG: installment must be positive'; END IF;
  IF p_total_months <= 0 THEN RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG: total_months must be positive'; END IF;
  IF p_total_months > 60 THEN RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG: total_months exceeds 60'; END IF;
  IF p_payout_month < 1 OR p_payout_month > p_total_months THEN RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG: payout_month must be within total_months'; END IF;

  -- 1. Create ALLOCATED wallet for the gameya reserve
  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (p_family_id, 'صندوق جمعية: ' || p_name, 'ALLOCATED', 0, v_m.id)
  RETURNING id INTO v_wallet_id;

  -- 2. Create the Gameya Circle
  INSERT INTO public.gameya_circles (
    family_id, name, monthly_installment, total_months, payout_month, start_date, wallet_id, created_by
  ) VALUES (
    p_family_id, p_name, p_monthly_installment, p_total_months, p_payout_month, p_start_date, v_wallet_id, v_m.id
  ) RETURNING id INTO v_gameya_id;

  -- 3. Generate Turns
  FOR v_i IN 1..p_total_months LOOP
    INSERT INTO public.gameya_turns (
      gameya_id, family_id, turn_number, due_date, status
    ) VALUES (
      v_gameya_id, p_family_id, v_i, p_start_date + make_interval(months => v_i - 1), 'UPCOMING'
    );
  END LOOP;

  -- 4. Audit
  INSERT INTO public.audit_events (family_id, action, actor_id, target_type, target_id, details)
  VALUES (p_family_id, 'GAMEYA_CREATED', v_m.id, 'gameya', v_gameya_id, jsonb_build_object(
    'name', p_name, 'total_months', p_total_months, 'wallet_id', v_wallet_id
  ));

  RETURN v_gameya_id;
END; $$;

-- =============================================================================
-- 2. Create Budget
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_create_budget(
  p_family_id UUID,
  p_category_id UUID,
  p_cycle_start DATE,
  p_cycle_end DATE,
  p_allocated_amount NUMERIC(14,2),
  p_period public.budget_period
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m public.family_members;
  v_cat public.categories;
  v_budget_id UUID;
  v_spent NUMERIC(14,2) := 0;
BEGIN
  v_m := public._require_member(p_family_id);

  IF p_allocated_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF p_cycle_end <= p_cycle_start THEN RAISE EXCEPTION 'INVALID_DATE_RANGE'; END IF;

  -- Verify category
  SELECT * INTO v_cat FROM public.categories WHERE id = p_category_id AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CATEGORY_NOT_FOUND'; END IF;
  IF v_cat.direction != 'EXPENSE' THEN RAISE EXCEPTION 'INVALID_CATEGORY_DIRECTION'; END IF;
  IF v_cat.family_id IS NOT NULL AND v_cat.family_id != p_family_id THEN
    RAISE EXCEPTION 'CATEGORY_NOT_FOUND';
  END IF;

  -- Duplicate check
  IF EXISTS (SELECT 1 FROM public.budgets WHERE family_id = p_family_id AND category_id = p_category_id AND cycle_start = p_cycle_start) THEN
    RAISE EXCEPTION 'DUPLICATE_BUDGET';
  END IF;

  -- Backfill spent amount based only on valid POSTED EXPENSES
  SELECT COALESCE(SUM(amount), 0) INTO v_spent
  FROM public.ledger_transactions
  WHERE family_id = p_family_id
    AND category_id = p_category_id
    AND type = 'EXPENSE'
    AND status = 'POSTED'
    AND effective_at >= p_cycle_start::timestamptz
    AND effective_at < (p_cycle_end + interval '1 day')::timestamptz;

  -- Create budget
  INSERT INTO public.budgets (
    family_id, category_id, cycle_start, cycle_end, allocated_amount, spent_amount, period
  ) VALUES (
    p_family_id, p_category_id, p_cycle_start, p_cycle_end, p_allocated_amount, v_spent, p_period
  ) RETURNING id INTO v_budget_id;

  -- Audit
  INSERT INTO public.audit_events (family_id, action, actor_id, target_type, target_id, details)
  VALUES (p_family_id, 'BUDGET_CREATED', v_m.id, 'budget', v_budget_id, jsonb_build_object(
    'allocated_amount', p_allocated_amount, 'initial_spent', v_spent
  ));

  RETURN v_budget_id;
END; $$;

-- =============================================================================
-- 3. Create Commitment
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_create_commitment(
  p_family_id UUID,
  p_name TEXT,
  p_category_id UUID,
  p_amount NUMERIC(14,2),
  p_frequency public.commitment_freq,
  p_start_date DATE,
  p_end_date DATE DEFAULT NULL,
  p_wallet_id UUID DEFAULT NULL,
  p_priority_level INTEGER DEFAULT 50,
  p_auto_deduct BOOLEAN DEFAULT false
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m public.family_members;
  v_cat public.categories;
  v_wallet public.wallets;
  v_commitment_id UUID;
  v_max_occurrences INTEGER;
  v_i INTEGER;
  v_due_date DATE;
BEGIN
  v_m := public._require_member(p_family_id);

  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF p_end_date IS NOT NULL AND p_end_date < p_start_date THEN RAISE EXCEPTION 'INVALID_DATE_RANGE'; END IF;

  -- Verify category
  SELECT * INTO v_cat FROM public.categories WHERE id = p_category_id AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CATEGORY_NOT_FOUND'; END IF;
  IF v_cat.direction != 'EXPENSE' THEN RAISE EXCEPTION 'INVALID_CATEGORY_DIRECTION'; END IF;
  IF v_cat.family_id IS NOT NULL AND v_cat.family_id != p_family_id THEN
    RAISE EXCEPTION 'CATEGORY_NOT_FOUND';
  END IF;

  -- Verify wallet if provided
  IF p_wallet_id IS NOT NULL THEN
    SELECT * INTO v_wallet FROM public.wallets WHERE id = p_wallet_id AND family_id = p_family_id AND NOT is_archived FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  END IF;

  -- Create commitment
  INSERT INTO public.commitments (
    family_id, name, category_id, amount, frequency, wallet_id, start_date, end_date, priority_level, auto_deduct, created_by
  ) VALUES (
    p_family_id, p_name, p_category_id, p_amount, p_frequency, p_wallet_id, p_start_date, p_end_date, p_priority_level, p_auto_deduct, v_m.id
  ) RETURNING id INTO v_commitment_id;

  -- Determine occurrence limits
  IF p_frequency = 'MONTHLY' THEN
    v_max_occurrences := 12;
  ELSIF p_frequency = 'QUARTERLY' THEN
    v_max_occurrences := 4;
  ELSIF p_frequency = 'SEMI_ANNUAL' THEN
    v_max_occurrences := 2;
  ELSIF p_frequency = 'ANNUAL' THEN
    v_max_occurrences := 1;
  ELSIF p_frequency = 'ONE_TIME' THEN
    v_max_occurrences := 1;
  END IF;

  -- Generate occurrences up to max limit or end_date
  FOR v_i IN 0..(v_max_occurrences - 1) LOOP
    v_due_date := CASE p_frequency
      WHEN 'MONTHLY' THEN p_start_date + make_interval(months => v_i)
      WHEN 'QUARTERLY' THEN p_start_date + make_interval(months => v_i * 3)
      WHEN 'SEMI_ANNUAL' THEN p_start_date + make_interval(months => v_i * 6)
      WHEN 'ANNUAL' THEN p_start_date + make_interval(years => v_i)
      WHEN 'ONE_TIME' THEN p_start_date
    END;
    
    -- Stop if we passed the end_date
    IF p_end_date IS NOT NULL AND v_due_date > p_end_date THEN
      EXIT;
    END IF;

    INSERT INTO public.commitment_occurrences (
      commitment_id, family_id, due_date, amount, status
    ) VALUES (
      v_commitment_id, p_family_id, v_due_date, p_amount, 'UPCOMING'
    );
  END LOOP;

  -- Audit
  INSERT INTO public.audit_events (family_id, action, actor_id, target_type, target_id, details)
  VALUES (p_family_id, 'COMMITMENT_CREATED', v_m.id, 'commitment', v_commitment_id, jsonb_build_object(
    'amount', p_amount, 'frequency', p_frequency
  ));

  RETURN v_commitment_id;
END; $$;

-- =============================================================================
-- 4. Pay Commitment Occurrence
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_pay_commitment_occurrence(
  p_family_id UUID,
  p_occurrence_id UUID,
  p_wallet_id UUID,
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
BEGIN
  v_m := public._require_member(p_family_id);

  -- 1. Lock Occurrence
  SELECT * INTO v_occ FROM public.commitment_occurrences WHERE id = p_occurrence_id AND family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'COMMITMENT_NOT_FOUND'; END IF;
  IF v_occ.status NOT IN ('UPCOMING', 'OVERDUE') THEN RAISE EXCEPTION 'OCCURRENCE_NOT_PAYABLE'; END IF;

  -- 2. Lock Commitment with family_id check
  SELECT * INTO v_com FROM public.commitments WHERE id = v_occ.commitment_id AND family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'COMMITMENT_NOT_FOUND'; END IF;

  -- 3. Lock Wallet
  SELECT * INTO v_w FROM public.wallets WHERE id = p_wallet_id AND family_id = p_family_id AND NOT is_archived AND type = 'REAL' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  IF v_w.balance < v_occ.amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;

  -- 4. Record Expense Ledger Transaction
  INSERT INTO public.ledger_transactions (
    family_id, type, amount, from_wallet_id, category_id, description, effective_at, created_by, notes
  ) VALUES (
    p_family_id, 'EXPENSE', v_occ.amount, p_wallet_id, v_com.category_id, 'دفع التزام: ' || v_com.name, p_effective_at, v_m.id, p_notes
  ) RETURNING id INTO v_txn_id;

  -- 5. Update Wallet
  UPDATE public.wallets SET balance = balance - v_occ.amount WHERE id = p_wallet_id;

  -- 6. Update Budget if exists
  UPDATE public.budgets
  SET spent_amount = spent_amount + v_occ.amount
  WHERE family_id = p_family_id
    AND category_id = v_com.category_id
    AND p_effective_at::date BETWEEN cycle_start AND cycle_end;

  -- 7. Mark Occurrence as Paid
  UPDATE public.commitment_occurrences
  SET status = 'PAID', paid_transaction_id = v_txn_id, paid_at = now()
  WHERE id = p_occurrence_id;

  -- 8. Audit
  INSERT INTO public.audit_events (family_id, action, actor_id, target_type, target_id, details)
  VALUES (p_family_id, 'COMMITMENT_PAID', v_m.id, 'commitment', v_com.id, jsonb_build_object(
    'occurrence_id', p_occurrence_id, 'amount', v_occ.amount, 'transaction_id', v_txn_id
  ));

  RETURN v_txn_id;
END; $$;

-- =============================================================================
-- 5. Fix Safe to Spend Calculation (Double Deduction Bug)
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
  SELECT COALESCE(SUM(LEAST(COALESCE(monthly_installment, remaining_amount), remaining_amount)), 0) INTO v_debts
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

-- =============================================================================
-- GRANTS & REVOKES
-- =============================================================================
REVOKE ALL ON FUNCTION public.fn_create_gameya_circle(UUID, TEXT, NUMERIC(14,2), INTEGER, INTEGER, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_create_gameya_circle(UUID, TEXT, NUMERIC(14,2), INTEGER, INTEGER, DATE) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_create_budget(UUID, UUID, DATE, DATE, NUMERIC(14,2), public.budget_period) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_create_budget(UUID, UUID, DATE, DATE, NUMERIC(14,2), public.budget_period) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_create_commitment(UUID, TEXT, UUID, NUMERIC(14,2), public.commitment_freq, DATE, DATE, UUID, INTEGER, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_create_commitment(UUID, TEXT, UUID, NUMERIC(14,2), public.commitment_freq, DATE, DATE, UUID, INTEGER, BOOLEAN) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_pay_commitment_occurrence(UUID, UUID, UUID, TIMESTAMPTZ, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_pay_commitment_occurrence(UUID, UUID, UUID, TIMESTAMPTZ, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_calculate_safe_to_spend(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_calculate_safe_to_spend(UUID) TO authenticated;
