-- =============================================================================
-- Mezan: 00024_flexible_gameya_atomic_rpcs.sql
-- Phase 7C: Flexible Gameya Atomic RPCs
-- =============================================================================

-- 1. Internal Helper Functions
CREATE OR REPLACE FUNCTION public._gameya_next_due_date(start_date DATE, frequency TEXT, step INT)
RETURNS DATE LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE frequency
    WHEN 'DAILY' THEN start_date + step
    WHEN 'WEEKLY' THEN start_date + (step * 7)
    WHEN 'BIWEEKLY' THEN start_date + (step * 14)
    WHEN 'SEMI_MONTHLY' THEN start_date + make_interval(days => step * 15)
    WHEN 'MONTHLY' THEN start_date + make_interval(months => step)
    ELSE start_date
  END;
$$;

CREATE OR REPLACE FUNCTION public._gameya_generate_installment_count(start_date DATE, end_date DATE, payment_frequency TEXT)
RETURNS INT LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_count INT := 0;
  v_current DATE := start_date;
BEGIN
  IF start_date > end_date THEN RETURN 0; END IF;
  WHILE v_current <= end_date LOOP
    v_count := v_count + 1;
    v_current := public._gameya_next_due_date(start_date, payment_frequency, v_count);
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public._gameya_payout_due_date(start_date DATE, turn_frequency TEXT, payout_turn INT)
RETURNS DATE LANGUAGE sql IMMUTABLE AS $$
  SELECT public._gameya_next_due_date(start_date, turn_frequency, payout_turn - 1);
$$;

REVOKE ALL ON FUNCTION public._gameya_next_due_date(DATE, TEXT, INT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gameya_generate_installment_count(DATE, DATE, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gameya_payout_due_date(DATE, TEXT, INT) FROM PUBLIC, anon, authenticated;

-- 2. Atomic RPCs

-- A. fn_create_flexible_gameya_circle
CREATE OR REPLACE FUNCTION public.fn_create_flexible_gameya_circle(
  p_family_id uuid,
  p_name text,
  p_installment_amount numeric,
  p_payment_frequency public.gameya_payment_frequency,
  p_turn_frequency public.gameya_turn_frequency,
  p_total_turns int,
  p_payout_turn int,
  p_start_date date
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m public.family_members;
  v_wallet_id UUID;
  v_gameya_id UUID;
  v_end_date DATE;
  v_installment_count INT;
  v_flex_payout_amount NUMERIC(14,2);
  v_i INT;
  v_expected_payout_date DATE;
BEGIN
  v_m := public._require_member(p_family_id);

  IF p_installment_amount <= 0 THEN RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG'; END IF;
  IF p_total_turns <= 0 OR p_total_turns > 100 THEN RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG'; END IF;
  IF p_payout_turn < 1 OR p_payout_turn > p_total_turns THEN RAISE EXCEPTION 'GAMEYA_INVALID_PAYOUT_TURN'; END IF;

  v_end_date := public._gameya_next_due_date(p_start_date, p_turn_frequency::text, p_total_turns - 1);
  v_expected_payout_date := public._gameya_payout_due_date(p_start_date, p_turn_frequency::text, p_payout_turn);
  v_installment_count := public._gameya_generate_installment_count(p_start_date, v_end_date, p_payment_frequency::text);
  
  IF v_installment_count > 500 THEN RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG'; END IF;
  
  v_flex_payout_amount := p_installment_amount * v_installment_count;

  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (p_family_id, convert_from(decode('2LXZhtiv2YjZgiDYrNmF2LnZitipOiA=', 'base64'), 'UTF8') || p_name, 'ALLOCATED', 0, v_m.id)
  RETURNING id INTO v_wallet_id;

  INSERT INTO public.gameya_circles (
    family_id, name, monthly_installment, total_months, payout_month, start_date, wallet_id, created_by,
    installment_amount, payment_frequency, turn_frequency, total_turns, payout_turn, expected_payout_date,
    flex_payout_amount, is_flexible
  ) VALUES (
    p_family_id, p_name, p_installment_amount, p_total_turns, p_payout_turn, p_start_date, v_wallet_id, v_m.id,
    p_installment_amount, p_payment_frequency, p_turn_frequency, p_total_turns, p_payout_turn, v_expected_payout_date,
    v_flex_payout_amount, true
  ) RETURNING id INTO v_gameya_id;

  FOR v_i IN 1..p_total_turns LOOP
    INSERT INTO public.gameya_turns (
      gameya_id, family_id, turn_number, due_date, status
    ) VALUES (
      v_gameya_id, p_family_id, v_i, public._gameya_next_due_date(p_start_date, p_turn_frequency::text, v_i - 1), 'UPCOMING'
    );
  END LOOP;

  FOR v_i IN 1..v_installment_count LOOP
    INSERT INTO public.gameya_installments (
      gameya_id, family_id, installment_number, due_date, amount, status
    ) VALUES (
      v_gameya_id, p_family_id, v_i, public._gameya_next_due_date(p_start_date, p_payment_frequency::text, v_i - 1), p_installment_amount, 'UPCOMING'
    );
  END LOOP;

  RETURN v_gameya_id;
END; $$;

-- B. fn_record_gameya_installment_payment
CREATE OR REPLACE FUNCTION public.fn_record_gameya_installment_payment(
  p_family_id uuid,
  p_installment_id uuid,
  p_real_wallet_id uuid,
  p_effective_at timestamptz default now()
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m public.family_members;
  v_inst public.gameya_installments;
  v_gameya public.gameya_circles;
  v_real_w public.wallets;
  v_alloc_w public.wallets;
  v_txn_id UUID;
BEGIN
  v_m := public._require_member(p_family_id);

  SELECT * INTO v_inst FROM public.gameya_installments WHERE id = p_installment_id AND family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAMEYA_INSTALLMENT_NOT_FOUND'; END IF;
  IF v_inst.status NOT IN ('UPCOMING', 'OVERDUE') THEN RAISE EXCEPTION 'GAMEYA_INSTALLMENT_ALREADY_PAID'; END IF;

  SELECT * INTO v_gameya FROM public.gameya_circles WHERE id = v_inst.gameya_id AND family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAMEYA_NOT_FOUND'; END IF;
  
  -- Deterministic Wallet Locking
  IF p_real_wallet_id < v_gameya.wallet_id THEN
    SELECT * INTO v_real_w FROM public.wallets WHERE id = p_real_wallet_id AND family_id = p_family_id AND type = 'REAL' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
    SELECT * INTO v_alloc_w FROM public.wallets WHERE id = v_gameya.wallet_id AND family_id = p_family_id AND type = 'ALLOCATED' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  ELSE
    SELECT * INTO v_alloc_w FROM public.wallets WHERE id = v_gameya.wallet_id AND family_id = p_family_id AND type = 'ALLOCATED' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
    SELECT * INTO v_real_w FROM public.wallets WHERE id = p_real_wallet_id AND family_id = p_family_id AND type = 'REAL' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  END IF;

  IF v_real_w.balance < v_inst.amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;

  INSERT INTO public.ledger_transactions (
    family_id, type, amount, from_wallet_id, to_wallet_id, description, effective_at, created_by
  ) VALUES (
    p_family_id, 'GAMEYA_INSTALLMENT', v_inst.amount, p_real_wallet_id, v_gameya.wallet_id, convert_from(decode('2K/Zgdi5INmC2LPYtyDYrNmF2LnZitipOiA=', 'base64'), 'UTF8') || v_gameya.name, p_effective_at, v_m.id
  ) RETURNING id INTO v_txn_id;

  UPDATE public.wallets SET balance = balance - v_inst.amount WHERE id = p_real_wallet_id;
  UPDATE public.wallets SET balance = balance + v_inst.amount WHERE id = v_gameya.wallet_id;

  UPDATE public.gameya_installments SET status = 'PAID', transaction_id = v_txn_id, paid_at = p_effective_at WHERE id = p_installment_id;

  RETURN v_txn_id;
END; $$;

-- C. fn_receive_flexible_gameya_payout
CREATE OR REPLACE FUNCTION public.fn_receive_flexible_gameya_payout(
  p_family_id uuid,
  p_gameya_id uuid,
  p_real_wallet_id uuid,
  p_effective_at timestamptz default now()
) RETURNS TABLE(transaction_id uuid, debt_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m public.family_members;
  v_gameya public.gameya_circles;
  v_alloc_w public.wallets;
  v_real_w public.wallets;
  v_turn public.gameya_turns;
  v_txn_id UUID;
  v_turn_txn_id UUID := NULL;
  v_debt_id UUID := NULL;
  v_allocated_balance NUMERIC(14,2);
  v_payout_amount NUMERIC(14,2);
  v_gap NUMERIC(14,2);
  v_unpaid_installments INT;
BEGIN
  v_m := public._require_member(p_family_id);

  SELECT * INTO v_gameya FROM public.gameya_circles WHERE id = p_gameya_id AND family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAMEYA_NOT_FOUND'; END IF;
  
  IF EXISTS (SELECT 1 FROM public.gameya_turns WHERE gameya_id = p_gameya_id AND status = 'RECEIVED') THEN
    RAISE EXCEPTION 'GAMEYA_PAYOUT_ALREADY_RECEIVED';
  END IF;

  SELECT * INTO v_turn FROM public.gameya_turns WHERE gameya_id = p_gameya_id AND turn_number = COALESCE(v_gameya.payout_turn, v_gameya.payout_month) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAMEYA_INVALID_PAYOUT_TURN'; END IF;

  -- Deterministic Wallet Locking
  IF p_real_wallet_id < v_gameya.wallet_id THEN
    SELECT * INTO v_real_w FROM public.wallets WHERE id = p_real_wallet_id AND family_id = p_family_id AND type = 'REAL' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
    SELECT * INTO v_alloc_w FROM public.wallets WHERE id = v_gameya.wallet_id AND family_id = p_family_id AND type = 'ALLOCATED' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  ELSE
    SELECT * INTO v_alloc_w FROM public.wallets WHERE id = v_gameya.wallet_id AND family_id = p_family_id AND type = 'ALLOCATED' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
    SELECT * INTO v_real_w FROM public.wallets WHERE id = p_real_wallet_id AND family_id = p_family_id AND type = 'REAL' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  END IF;

  v_allocated_balance := v_alloc_w.balance;
  v_payout_amount := COALESCE(v_gameya.flex_payout_amount, v_gameya.payout_amount);

  IF v_allocated_balance > v_payout_amount THEN
    RAISE EXCEPTION 'GAMEYA_RESERVE_OVERFUNDED';
  END IF;

  IF v_allocated_balance > 0 THEN
    INSERT INTO public.ledger_transactions (
      family_id, type, amount, from_wallet_id, to_wallet_id, description, effective_at, created_by
    ) VALUES (
      p_family_id, 'GAMEYA_PAYOUT', v_allocated_balance, v_alloc_w.id, v_real_w.id, convert_from(decode('2KfYs9iq2YTYp9mFINix2LXZitivINmF2K7Ytdi1INmE2KzZhdi52YrYqTog', 'base64'), 'UTF8') || v_gameya.name, p_effective_at, v_m.id
    ) RETURNING id INTO v_txn_id;

    UPDATE public.wallets SET balance = balance - v_allocated_balance WHERE id = v_alloc_w.id;
    UPDATE public.wallets SET balance = balance + v_allocated_balance WHERE id = v_real_w.id;
    
    v_turn_txn_id := v_txn_id;
  END IF;

  IF v_payout_amount > v_allocated_balance THEN
    v_gap := v_payout_amount - v_allocated_balance;
    
    -- Option A: one-time liability with monthly_installment = NULL
    INSERT INTO public.debts (
      family_id, entity_name, direction, original_amount, remaining_amount, created_by, status, due_date, monthly_installment
    ) VALUES (
      p_family_id, convert_from(decode('2KzZhdi52YrYqTog', 'base64'), 'UTF8') || v_gameya.name, 'BORROWED_FROM', v_gap, v_gap, v_m.id, 'ACTIVE', v_gameya.expected_payout_date, NULL
    ) RETURNING id INTO v_debt_id;

    INSERT INTO public.ledger_transactions (
      family_id, type, amount, to_wallet_id, description, effective_at, created_by
    ) VALUES (
      p_family_id, 'LOAN_RECEIVE', v_gap, v_real_w.id, convert_from(decode('2YHYsdmCINmC2KjYtiDZhdio2YPYsSDZhNis2YXYudmK2Kk6IA==', 'base64'), 'UTF8') || v_gameya.name, p_effective_at, v_m.id
    ) RETURNING id INTO v_txn_id;

    UPDATE public.wallets SET balance = balance + v_gap WHERE id = v_real_w.id;
    
    IF v_turn_txn_id IS NULL THEN
      v_turn_txn_id := v_txn_id;
    END IF;
    debt_id := v_debt_id;
    
    -- Cancel all unpaid installments to prevent double obligation
    UPDATE public.gameya_installments 
    SET status = 'CANCELLED' 
    WHERE gameya_id = p_gameya_id 
      AND status IN ('UPCOMING', 'OVERDUE') 
      AND transaction_id IS NULL;
  END IF;

  UPDATE public.gameya_turns 
  SET status = 'RECEIVED', transaction_id = v_turn_txn_id, paid_at = p_effective_at
  WHERE id = v_turn.id;

  SELECT COUNT(*) INTO v_unpaid_installments FROM public.gameya_installments WHERE gameya_id = p_gameya_id AND status IN ('UPCOMING', 'OVERDUE');
  
  IF v_debt_id IS NOT NULL THEN
    UPDATE public.gameya_circles SET status = 'RECEIVED_PAYING_DEBT' WHERE id = p_gameya_id;
  ELSIF v_unpaid_installments = 0 THEN
    UPDATE public.gameya_circles SET status = 'COMPLETED' WHERE id = p_gameya_id;
  END IF;

  transaction_id := v_turn_txn_id;
  RETURN NEXT;
  RETURN;
END; $$;

-- D. fn_change_gameya_payout_turn
CREATE OR REPLACE FUNCTION public.fn_change_gameya_payout_turn(
  p_family_id uuid,
  p_gameya_id uuid,
  p_new_payout_turn int
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m public.family_members;
  v_gameya public.gameya_circles;
  v_new_date DATE;
BEGIN
  v_m := public._require_member(p_family_id);

  SELECT * INTO v_gameya FROM public.gameya_circles WHERE id = p_gameya_id AND family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAMEYA_NOT_FOUND'; END IF;

  IF v_gameya.status != 'SAVING_PHASE' THEN RAISE EXCEPTION 'GAMEYA_SCHEDULE_LOCKED'; END IF;
  
  IF EXISTS (SELECT 1 FROM public.gameya_turns WHERE gameya_id = p_gameya_id AND status = 'RECEIVED') THEN
    RAISE EXCEPTION 'GAMEYA_SCHEDULE_LOCKED';
  END IF;
  
  IF EXISTS (SELECT 1 FROM public.ledger_transactions WHERE type = 'GAMEYA_PAYOUT' AND from_wallet_id = v_gameya.wallet_id) THEN
    RAISE EXCEPTION 'GAMEYA_SCHEDULE_LOCKED';
  END IF;

  IF p_new_payout_turn < 1 OR p_new_payout_turn > COALESCE(v_gameya.total_turns, v_gameya.total_months) THEN
    RAISE EXCEPTION 'GAMEYA_INVALID_PAYOUT_TURN';
  END IF;

  v_new_date := public._gameya_payout_due_date(v_gameya.start_date, v_gameya.turn_frequency::text, p_new_payout_turn);

  IF EXISTS (
    SELECT 1 FROM public.gameya_installments 
    WHERE gameya_id = p_gameya_id AND status = 'PAID' AND due_date > v_new_date
  ) THEN
    RAISE EXCEPTION 'GAMEYA_SCHEDULE_LOCKED';
  END IF;

  UPDATE public.gameya_circles 
  SET payout_turn = p_new_payout_turn, payout_month = p_new_payout_turn, expected_payout_date = v_new_date
  WHERE id = p_gameya_id;
END; $$;

-- E. fn_update_gameya_future_schedule
CREATE OR REPLACE FUNCTION public.fn_update_gameya_future_schedule(
  p_family_id uuid,
  p_gameya_id uuid,
  p_new_installment_amount numeric,
  p_new_payment_frequency public.gameya_payment_frequency
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m public.family_members;
  v_gameya public.gameya_circles;
  v_last_locked_inst public.gameya_installments;
  v_new_count INT;
  v_end_date DATE;
  v_start_date DATE;
  v_i INT;
  v_total_paid_count INT;
  v_total_amt NUMERIC(14,2);
BEGIN
  v_m := public._require_member(p_family_id);

  SELECT * INTO v_gameya FROM public.gameya_circles WHERE id = p_gameya_id AND family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAMEYA_NOT_FOUND'; END IF;

  IF p_new_installment_amount <= 0 THEN RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG'; END IF;

  SELECT * INTO v_last_locked_inst 
  FROM public.gameya_installments 
  WHERE gameya_id = p_gameya_id 
    AND (status IN ('PAID', 'OVERDUE') OR transaction_id IS NOT NULL OR due_date <= CURRENT_DATE)
  ORDER BY installment_number DESC LIMIT 1;

  IF v_last_locked_inst IS NULL THEN
    v_start_date := v_gameya.start_date;
    v_total_paid_count := 0;
  ELSE
    v_start_date := public._gameya_next_due_date(v_last_locked_inst.due_date, p_new_payment_frequency::text, 1);
    v_total_paid_count := v_last_locked_inst.installment_number;
  END IF;

  v_end_date := public._gameya_next_due_date(v_gameya.start_date, v_gameya.turn_frequency::text, v_gameya.total_turns - 1);

  IF v_start_date <= v_end_date THEN
    v_new_count := public._gameya_generate_installment_count(v_start_date, v_end_date, p_new_payment_frequency::text);
    
    IF v_new_count > 500 THEN
      RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG';
    END IF;

    DELETE FROM public.gameya_installments 
    WHERE gameya_id = p_gameya_id 
      AND status = 'UPCOMING' 
      AND transaction_id IS NULL 
      AND due_date > CURRENT_DATE;

    FOR v_i IN 1..v_new_count LOOP
      INSERT INTO public.gameya_installments (
        gameya_id, family_id, installment_number, due_date, amount, status
      ) VALUES (
        p_gameya_id, p_family_id, v_total_paid_count + v_i, 
        public._gameya_next_due_date(v_start_date, p_new_payment_frequency::text, v_i - 1), 
        p_new_installment_amount, 'UPCOMING'
      );
    END LOOP;
  END IF;

  SELECT SUM(amount) INTO v_total_amt FROM public.gameya_installments WHERE gameya_id = p_gameya_id;
  
  UPDATE public.gameya_circles 
  SET installment_amount = p_new_installment_amount, 
      payment_frequency = p_new_payment_frequency,
      flex_payout_amount = COALESCE(v_total_amt, 0)
  WHERE id = p_gameya_id;

END; $$;

-- 3. Grants
REVOKE ALL ON FUNCTION public.fn_create_flexible_gameya_circle(UUID, TEXT, NUMERIC, public.gameya_payment_frequency, public.gameya_turn_frequency, INT, INT, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_create_flexible_gameya_circle(UUID, TEXT, NUMERIC, public.gameya_payment_frequency, public.gameya_turn_frequency, INT, INT, DATE) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_record_gameya_installment_payment(UUID, UUID, UUID, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_record_gameya_installment_payment(UUID, UUID, UUID, TIMESTAMPTZ) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_receive_flexible_gameya_payout(UUID, UUID, UUID, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_receive_flexible_gameya_payout(UUID, UUID, UUID, TIMESTAMPTZ) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_change_gameya_payout_turn(UUID, UUID, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_change_gameya_payout_turn(UUID, UUID, INT) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_update_gameya_future_schedule(UUID, UUID, NUMERIC, public.gameya_payment_frequency) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_update_gameya_future_schedule(UUID, UUID, NUMERIC, public.gameya_payment_frequency) TO authenticated;
