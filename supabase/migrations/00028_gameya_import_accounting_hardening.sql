-- =============================================================================
-- Mezan: 00028_gameya_import_accounting_hardening.sql
-- Phase 8C: Gameya Logic & Accounting Hardening
-- =============================================================================

-- 1. Create fn_update_gameya_name to avoid direct table mutations
CREATE OR REPLACE FUNCTION public.fn_update_gameya_name(
  p_family_id uuid,
  p_gameya_id uuid,
  p_name text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public._require_member(p_family_id);

  UPDATE public.gameya_circles 
  SET name = p_name
  WHERE id = p_gameya_id AND family_id = p_family_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'GAMEYA_NOT_FOUND';
  END IF;
END; $$;

REVOKE ALL ON FUNCTION public.fn_update_gameya_name(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_update_gameya_name(UUID, UUID, TEXT) TO authenticated;


-- 2. Override fn_import_existing_gameya_circle
CREATE OR REPLACE FUNCTION public.fn_import_existing_gameya_circle(
  p_family_id uuid,
  p_name text,
  p_installment_amount numeric,
  p_payment_frequency public.gameya_payment_frequency,
  p_turn_frequency public.gameya_turn_frequency,
  p_total_turns int,
  p_payout_turn int,
  p_original_start_date date,
  p_tracking_start_date date,
  p_paid_installments_count int,
  p_has_received_payout boolean,
  p_received_payout_amount numeric,
  p_remaining_amount numeric,
  p_effective_at timestamptz default now()
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m public.family_members;
  v_alloc_w public.wallets;
  v_real_w public.wallets;
  v_gameya_id uuid;
  v_total_paid_amount numeric(14,2);
  v_end_date date;
  v_expected_payout_date date;
  v_installment_count int;
  v_i int;
  v_current_due date;
  v_status public.occurrence_status;
  v_turn_due date;
  v_turn_status public.gameya_turn_status;
  v_debt_id uuid := NULL;
  v_opening_txn_id uuid := NULL;
BEGIN
  v_m := public._require_member(p_family_id);

  -- Wallet Discovery
  SELECT * INTO v_alloc_w FROM public.wallets WHERE family_id = p_family_id AND type = 'ALLOCATED' AND NOT is_archived ORDER BY created_at ASC LIMIT 1;
  IF NOT FOUND THEN
    INSERT INTO public.wallets (family_id, name, type, created_by) VALUES (p_family_id, convert_from(decode('2YXYrdmB2LjYqSDYp9mE2KzZhdi52YrYp9iq', 'base64'), 'UTF8'), 'ALLOCATED', v_m.id) RETURNING * INTO v_alloc_w;
  END IF;

  SELECT * INTO v_real_w FROM public.wallets WHERE family_id = p_family_id AND type = 'REAL' AND NOT is_archived ORDER BY created_at ASC LIMIT 1;
  IF NOT FOUND THEN
    INSERT INTO public.wallets (family_id, name, type, created_by) VALUES (p_family_id, convert_from(decode('2KfZhNmF2K3Zgdi42Kkg2KfZhNix2KbZitiz2YrYqQ==', 'base64'), 'UTF8'), 'REAL', v_m.id) RETURNING * INTO v_real_w;
  END IF;

  v_end_date := public._gameya_next_due_date(p_original_start_date, p_turn_frequency::text, p_total_turns - 1);
  v_installment_count := public._gameya_generate_installment_count(p_original_start_date, v_end_date, p_payment_frequency::text);
  
  IF p_paid_installments_count > v_installment_count THEN
    RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG';
  END IF;

  v_total_paid_amount := p_paid_installments_count * p_installment_amount;
  v_expected_payout_date := public._gameya_next_due_date(p_original_start_date, p_turn_frequency::text, p_payout_turn - 1);

  -- Debt creation if paid out
  IF p_has_received_payout AND p_remaining_amount > 0 THEN
    INSERT INTO public.debts (
      family_id, entity_name, direction, original_amount, remaining_amount, created_by, status, due_date
    ) VALUES (
      p_family_id, convert_from(decode('2KzZhdi52YrYqTog', 'base64'), 'UTF8') || p_name, 'BORROWED_FROM', p_remaining_amount, p_remaining_amount, v_m.id, 'ACTIVE', v_expected_payout_date
    ) RETURNING id INTO v_debt_id;
  END IF;

  -- Create Circle
  INSERT INTO public.gameya_circles (
    family_id, name, wallet_id, created_by,
    monthly_installment, total_months, payout_month, start_date,
    installment_amount, payment_frequency, turn_frequency, total_turns, payout_turn,
    expected_payout_date, flex_payout_amount, is_flexible,
    status, payout_debt_id
  ) VALUES (
    p_family_id, p_name, v_alloc_w.id, v_m.id,
    p_installment_amount, p_total_turns, p_payout_turn, p_original_start_date,
    p_installment_amount, p_payment_frequency, p_turn_frequency, p_total_turns, p_payout_turn,
    v_expected_payout_date, p_installment_amount * v_installment_count, true,
    CASE 
      WHEN p_has_received_payout THEN 
        CASE WHEN p_remaining_amount > 0 THEN 'RECEIVED_PAYING_DEBT'::public.gameya_status ELSE 'COMPLETED'::public.gameya_status END
      ELSE 'SAVING_PHASE'::public.gameya_status 
    END,
    v_debt_id
  ) RETURNING id INTO v_gameya_id;

  -- Only create Opening Balance if NOT received payout AND has paid installments
  IF NOT p_has_received_payout AND v_total_paid_amount > 0 THEN
    INSERT INTO public.ledger_transactions (
      family_id, type, amount, to_wallet_id, description, effective_at, created_by
    ) VALUES (
      p_family_id, 'OPENING_BALANCE', v_total_paid_amount, v_alloc_w.id, convert_from(decode('2LHYtdmK2K8g2LPYp9io2YIg2YTYrNmF2LnZitipOiA=', 'base64'), 'UTF8') || p_name, p_tracking_start_date, v_m.id
    ) RETURNING id INTO v_opening_txn_id;

    UPDATE public.wallets SET balance = balance + v_total_paid_amount WHERE id = v_alloc_w.id;
  END IF;

  -- Generate Installments
  FOR v_i IN 1..v_installment_count LOOP
    v_current_due := public._gameya_next_due_date(p_original_start_date, p_payment_frequency::text, v_i - 1);
    
    IF v_i <= p_paid_installments_count THEN
      v_status := 'PAID';
    ELSIF p_has_received_payout THEN
      -- If already received payout, future installments are cancelled (debt takes over)
      v_status := 'CANCELLED';
    ELSE
      -- Not received payout, missed past tracking date are overdue
      IF v_current_due < p_tracking_start_date THEN
        v_status := 'OVERDUE';
      ELSE
        v_status := 'UPCOMING';
      END IF;
    END IF;

    INSERT INTO public.gameya_installments (
      gameya_id, family_id, installment_number, due_date, amount, status, transaction_id, paid_at
    ) VALUES (
      v_gameya_id, p_family_id, v_i, v_current_due, p_installment_amount, v_status,
      CASE WHEN v_status = 'PAID' AND NOT p_has_received_payout THEN v_opening_txn_id ELSE NULL END,
      CASE WHEN v_status = 'PAID' THEN p_tracking_start_date ELSE NULL END
    );
  END LOOP;

  -- Generate Turns
  FOR v_i IN 1..p_total_turns LOOP
    v_turn_due := public._gameya_next_due_date(p_original_start_date, p_turn_frequency::text, v_i - 1);
    
    IF v_i = p_payout_turn AND p_has_received_payout THEN
       v_turn_status := 'RECEIVED';
    ELSIF v_i < p_payout_turn AND p_has_received_payout THEN
       v_turn_status := 'RECEIVED'; -- assume others received
    ELSIF v_turn_due < p_tracking_start_date THEN
       v_turn_status := 'MISSED';
    ELSE
       v_turn_status := 'UPCOMING';
    END IF;

    INSERT INTO public.gameya_turns (
      gameya_id, family_id, turn_number, due_date, status, paid_at
    ) VALUES (
      v_gameya_id, p_family_id, v_i, v_turn_due, v_turn_status,
      CASE WHEN v_turn_status = 'RECEIVED' THEN p_tracking_start_date ELSE NULL END
    );
  END LOOP;

  RETURN v_gameya_id;
END; $$;


-- 3. Override fn_exit_flexible_gameya_circle
CREATE OR REPLACE FUNCTION public.fn_exit_flexible_gameya_circle(
  p_family_id uuid,
  p_gameya_id uuid,
  p_real_wallet_id uuid,
  p_settlement_mode text,
  p_effective_at timestamptz default now()
) RETURNS TABLE(
  refund_transaction_id uuid,
  settlement_transaction_id uuid,
  debt_id uuid,
  net_amount numeric
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_m public.family_members;
  v_gameya public.gameya_circles;
  v_real_w public.wallets;
  v_alloc_w public.wallets;
  v_total_paid NUMERIC(14,2);
  v_allocated_balance NUMERIC(14,2);
  v_payout_received NUMERIC(14,2);
  v_net_amount NUMERIC(14,2);
  v_refund_txn_id UUID := NULL;
  v_settle_txn_id UUID := NULL;
  v_debt_id UUID := NULL;
  v_has_payout BOOLEAN := FALSE;
  v_is_imported_payout BOOLEAN := FALSE;
  v_existing_debt public.debts;
  v_pay_amount NUMERIC(14,2);
BEGIN
  v_m := public._require_member(p_family_id);

  SELECT * INTO v_gameya FROM public.gameya_circles WHERE id = p_gameya_id AND family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAMEYA_NOT_FOUND'; END IF;
  IF v_gameya.status = 'CANCELLED' THEN RAISE EXCEPTION 'GAMEYA_ALREADY_CANCELLED'; END IF;
  IF v_gameya.status = 'COMPLETED' THEN RAISE EXCEPTION 'GAMEYA_ALREADY_COMPLETED'; END IF;

  -- Wallet Locking
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

  IF v_gameya.payout_transaction_id IS NOT NULL OR v_gameya.payout_loan_transaction_id IS NOT NULL THEN
    v_has_payout := TRUE;
  ELSIF EXISTS (SELECT 1 FROM public.gameya_turns WHERE gameya_id = p_gameya_id AND status = 'RECEIVED') THEN
    v_has_payout := TRUE;
    IF v_gameya.payout_debt_id IS NOT NULL AND v_gameya.payout_transaction_id IS NULL AND v_gameya.payout_loan_transaction_id IS NULL THEN
      v_is_imported_payout := TRUE;
    END IF;
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid FROM public.gameya_installments WHERE gameya_id = p_gameya_id AND status = 'PAID';

  IF NOT v_has_payout THEN
    v_allocated_balance := v_alloc_w.balance;
    IF v_allocated_balance < v_total_paid THEN
      RAISE EXCEPTION 'GAMEYA_EXIT_BALANCE_MISMATCH';
    END IF;

    IF v_total_paid > 0 THEN
      IF p_settlement_mode != 'REFUND_TO_WALLET' THEN
        RAISE EXCEPTION 'GAMEYA_INVALID_SETTLEMENT_MODE';
      END IF;

      INSERT INTO public.ledger_transactions (
        family_id, type, amount, from_wallet_id, to_wallet_id, description, effective_at, created_by
      ) VALUES (
        p_family_id, 'GAMEYA_PAYOUT', v_total_paid, v_alloc_w.id, v_real_w.id, convert_from(decode('2KfYs9iq2LHYrNin2Lkg2KzZhdi52YrYqTog', 'base64'), 'UTF8') || v_gameya.name, p_effective_at, v_m.id
      ) RETURNING id INTO v_refund_txn_id;

      UPDATE public.wallets SET balance = balance - v_total_paid WHERE id = v_alloc_w.id;
      UPDATE public.wallets SET balance = balance + v_total_paid WHERE id = v_real_w.id;
    ELSE
      IF p_settlement_mode NOT IN ('NOOP', 'REFUND_TO_WALLET') THEN
        RAISE EXCEPTION 'GAMEYA_INVALID_SETTLEMENT_MODE';
      END IF;
    END IF;

    v_net_amount := -v_total_paid;
  ELSE
    IF v_gameya.payout_transaction_id IS NULL AND v_gameya.payout_loan_transaction_id IS NULL AND NOT v_is_imported_payout THEN
      RAISE EXCEPTION 'GAMEYA_SETTLEMENT_REQUIRED';
    END IF;

    IF v_is_imported_payout THEN
       SELECT * INTO v_existing_debt FROM public.debts WHERE id = v_gameya.payout_debt_id AND family_id = p_family_id FOR UPDATE;
       v_net_amount := v_existing_debt.remaining_amount;
    ELSE
       v_payout_received := 0;
       IF v_gameya.payout_transaction_id IS NOT NULL THEN
         v_payout_received := v_payout_received + (SELECT amount FROM public.ledger_transactions WHERE id = v_gameya.payout_transaction_id);
       END IF;
       IF v_gameya.payout_loan_transaction_id IS NOT NULL THEN
         v_payout_received := v_payout_received + (SELECT amount FROM public.ledger_transactions WHERE id = v_gameya.payout_loan_transaction_id);
       END IF;
       
       v_net_amount := v_payout_received - v_total_paid;

       IF v_net_amount > 0 AND v_gameya.payout_debt_id IS NOT NULL THEN
         SELECT * INTO v_existing_debt FROM public.debts WHERE id = v_gameya.payout_debt_id AND family_id = p_family_id FOR UPDATE;
         v_net_amount := v_existing_debt.remaining_amount;
       END IF;
    END IF;

    IF v_net_amount > 0 THEN
      IF p_settlement_mode = 'PAY_NOW' THEN
        IF v_real_w.balance < v_net_amount THEN
          RAISE EXCEPTION 'INSUFFICIENT_BALANCE';
        END IF;

        IF v_gameya.payout_debt_id IS NOT NULL THEN
          v_pay_amount := v_net_amount;

          INSERT INTO public.ledger_transactions (
            family_id, type, amount, from_wallet_id, description, effective_at, created_by
          ) VALUES (
            p_family_id, 'LOAN_PAYMENT_OUT', v_pay_amount, v_real_w.id, convert_from(decode('2LPYrdiv2Kkg2KzZhdi52YrYqTog', 'base64'), 'UTF8') || v_gameya.name, p_effective_at, v_m.id
          ) RETURNING id INTO v_settle_txn_id;

          UPDATE public.wallets SET balance = balance - v_pay_amount WHERE id = v_real_w.id;
          
          UPDATE public.debts 
          SET remaining_amount = remaining_amount - v_pay_amount,
              status = CASE WHEN remaining_amount - v_pay_amount <= 0 THEN 'SETTLED'::public.debt_status ELSE status END
          WHERE id = v_existing_debt.id;

          INSERT INTO public.debt_payments (debt_id, family_id, transaction_id, amount) VALUES (v_existing_debt.id, p_family_id, v_settle_txn_id, v_pay_amount);
          
          v_debt_id := v_existing_debt.id;
        ELSE
          INSERT INTO public.debts (
            family_id, entity_name, direction, original_amount, remaining_amount, created_by, status, due_date
          ) VALUES (
            p_family_id, convert_from(decode('2KzZhdi52YrYqTog', 'base64'), 'UTF8') || v_gameya.name, 'BORROWED_FROM', v_net_amount, 0, v_m.id, 'SETTLED', p_effective_at::date
          ) RETURNING id INTO v_debt_id;

          INSERT INTO public.ledger_transactions (
            family_id, type, amount, from_wallet_id, description, effective_at, created_by
          ) VALUES (
            p_family_id, 'LOAN_PAYMENT_OUT', v_net_amount, v_real_w.id, convert_from(decode('2LPYrdiv2Kkg2KzZhdi52YrYqTog', 'base64'), 'UTF8') || v_gameya.name, p_effective_at, v_m.id
          ) RETURNING id INTO v_settle_txn_id;

          UPDATE public.wallets SET balance = balance - v_net_amount WHERE id = v_real_w.id;
          INSERT INTO public.debt_payments (debt_id, family_id, transaction_id, amount) VALUES (v_debt_id, p_family_id, v_settle_txn_id, v_net_amount);
        END IF;

      ELSIF p_settlement_mode = 'CONVERT_TO_DEBT' THEN
        IF v_gameya.payout_debt_id IS NOT NULL THEN
          v_debt_id := v_gameya.payout_debt_id;
        ELSE
          INSERT INTO public.debts (
            family_id, entity_name, direction, original_amount, remaining_amount, created_by, status, due_date
          ) VALUES (
            p_family_id, convert_from(decode('2KzZhdi52YrYqTog', 'base64'), 'UTF8') || v_gameya.name, 'BORROWED_FROM', v_net_amount, v_net_amount, v_m.id, 'ACTIVE', p_effective_at::date
          ) RETURNING id INTO v_debt_id;
        END IF;
      ELSE
        RAISE EXCEPTION 'GAMEYA_INVALID_SETTLEMENT_MODE';
      END IF;
    ELSIF v_net_amount = 0 AND p_settlement_mode != 'NOOP' THEN
       RAISE EXCEPTION 'GAMEYA_INVALID_SETTLEMENT_MODE';
    ELSIF v_net_amount < 0 THEN
      IF p_settlement_mode != 'REFUND_TO_WALLET' THEN
        RAISE EXCEPTION 'GAMEYA_INVALID_SETTLEMENT_MODE';
      END IF;

      IF v_alloc_w.balance < ABS(v_net_amount) THEN
        RAISE EXCEPTION 'GAMEYA_EXIT_BALANCE_MISMATCH';
      END IF;

      INSERT INTO public.ledger_transactions (
        family_id, type, amount, from_wallet_id, to_wallet_id, description, effective_at, created_by
      ) VALUES (
        p_family_id, 'GAMEYA_PAYOUT', ABS(v_net_amount), v_alloc_w.id, v_real_w.id, convert_from(decode('2KfYs9iq2LHYrNin2Lkg2KzZhdi52YrYqTog', 'base64'), 'UTF8') || v_gameya.name, p_effective_at, v_m.id
      ) RETURNING id INTO v_refund_txn_id;

      UPDATE public.wallets SET balance = balance - ABS(v_net_amount) WHERE id = v_alloc_w.id;
      UPDATE public.wallets SET balance = balance + ABS(v_net_amount) WHERE id = v_real_w.id;

    END IF;
  END IF;

  UPDATE public.gameya_installments gi
  SET status = 'CANCELLED'
  WHERE gi.gameya_id = p_gameya_id
    AND gi.status IN ('UPCOMING', 'OVERDUE')
    AND gi.transaction_id IS NULL;

  UPDATE public.gameya_circles 
  SET status = 'CANCELLED',
      payout_debt_id = COALESCE(v_gameya.payout_debt_id, v_debt_id)
  WHERE id = p_gameya_id;

  refund_transaction_id := v_refund_txn_id;
  settlement_transaction_id := v_settle_txn_id;
  debt_id := v_debt_id;
  net_amount := v_net_amount;
  RETURN NEXT;
  RETURN;
END; $$;


-- 4. Override fn_receive_flexible_gameya_payout
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
  v_payout_txn_id UUID := NULL;
  v_loan_txn_id UUID := NULL;
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

  IF v_gameya.status NOT IN ('SAVING_PHASE', 'COMPLETED') THEN 
    RAISE EXCEPTION 'GAMEYA_NOT_ACTIVE'; 
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
    ) RETURNING id INTO v_payout_txn_id;

    UPDATE public.wallets SET balance = balance - v_allocated_balance WHERE id = v_alloc_w.id;
    UPDATE public.wallets SET balance = balance + v_allocated_balance WHERE id = v_real_w.id;
    
    v_turn_txn_id := v_payout_txn_id;
  END IF;

  IF v_payout_amount > v_allocated_balance THEN
    v_gap := v_payout_amount - v_allocated_balance;
    
    -- Note: We set the due_date to p_effective_at::date so that the debt is immediately visible
    -- in the safe-to-spend dashboard as a liability for the current month.
    INSERT INTO public.debts (
      family_id, entity_name, direction, original_amount, remaining_amount, created_by, status, due_date, monthly_installment
    ) VALUES (
      p_family_id, convert_from(decode('2KzZhdi52YrYqTog', 'base64'), 'UTF8') || v_gameya.name, 'BORROWED_FROM', v_gap, v_gap, v_m.id, 'ACTIVE', p_effective_at::date, NULL
    ) RETURNING id INTO v_debt_id;

    INSERT INTO public.ledger_transactions (
      family_id, type, amount, to_wallet_id, description, effective_at, created_by
    ) VALUES (
      p_family_id, 'LOAN_RECEIVE', v_gap, v_real_w.id, convert_from(decode('2YHYsdmCINmC2KjYtiDZhdio2YPYsSDZhNis2YXYudmK2Kk6IA==', 'base64'), 'UTF8') || v_gameya.name, p_effective_at, v_m.id
    ) RETURNING id INTO v_loan_txn_id;

    UPDATE public.wallets SET balance = balance + v_gap WHERE id = v_real_w.id;
    
    IF v_turn_txn_id IS NULL THEN
      v_turn_txn_id := v_loan_txn_id;
    END IF;
    
    UPDATE public.gameya_installments gi
    SET status = 'CANCELLED' 
    WHERE gi.gameya_id = p_gameya_id 
      AND gi.status IN ('UPCOMING', 'OVERDUE') 
      AND gi.transaction_id IS NULL;
  END IF;

  UPDATE public.gameya_turns gt
  SET status = 'RECEIVED', transaction_id = v_turn_txn_id, paid_at = p_effective_at
  WHERE gt.id = v_turn.id;

  SELECT COUNT(*) INTO v_unpaid_installments FROM public.gameya_installments gi WHERE gi.gameya_id = p_gameya_id AND gi.status IN ('UPCOMING', 'OVERDUE');
  
  UPDATE public.gameya_circles gc 
  SET payout_transaction_id = v_payout_txn_id,
      payout_loan_transaction_id = v_loan_txn_id,
      payout_debt_id = v_debt_id,
      status = CASE 
                 WHEN v_debt_id IS NOT NULL THEN 'RECEIVED_PAYING_DEBT'::public.gameya_status
                 WHEN v_unpaid_installments = 0 THEN 'COMPLETED'::public.gameya_status
                 ELSE gc.status
               END
  WHERE gc.id = p_gameya_id;

  transaction_id := v_turn_txn_id;
  debt_id := v_debt_id;
  RETURN NEXT;
  RETURN;
END; $$;


-- 5. Override fn_calculate_safe_to_spend
CREATE OR REPLACE FUNCTION public.fn_calculate_safe_to_spend(p_family_id UUID)
RETURNS NUMERIC(14,2) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_real NUMERIC(14,2);
  v_commits NUMERIC(14,2);
  v_debts NUMERIC(14,2);
  v_gameya NUMERIC(14,2);
  v_gameya_flex NUMERIC(14,2);
  v_gameya_legacy NUMERIC(14,2);
  v_end_of_month DATE;
BEGIN
  PERFORM public._require_member(p_family_id, ARRAY['OWNER','MEMBER','VIEWER']::public.member_role[]);
  
  v_end_of_month := (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date;

  SELECT COALESCE(SUM(balance),0) INTO v_real 
  FROM public.wallets 
  WHERE family_id = p_family_id AND type = 'REAL' AND NOT is_archived;

  SELECT COALESCE(SUM(amount),0) INTO v_commits 
  FROM public.commitment_occurrences 
  WHERE family_id = p_family_id 
    AND status IN ('UPCOMING','OVERDUE')
    AND due_date <= v_end_of_month;

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

  -- Upcoming gameya installments due in current cycle
  -- Added Defensive Guard: Explicitly ignore CANCELLED, and ignore installments if payout_debt_id is active (prevent double-count)
  SELECT COALESCE(SUM(i.amount), 0) INTO v_gameya_flex
  FROM public.gameya_installments i
  JOIN public.gameya_circles c ON c.id = i.gameya_id
  WHERE i.family_id = p_family_id
    AND i.status IN ('UPCOMING', 'OVERDUE')
    AND i.due_date <= v_end_of_month
    AND c.payout_debt_id IS NULL; -- Prevent double-count if debt is active

  -- Upcoming gameya turns due in current cycle (Legacy Logic fallback)
  SELECT COALESCE(SUM(c.monthly_installment), 0) INTO v_gameya_legacy
  FROM public.gameya_turns t
  JOIN public.gameya_circles c ON t.gameya_id = c.id
  WHERE t.family_id = p_family_id
    AND t.status IN ('UPCOMING', 'MISSED')
    AND t.due_date <= v_end_of_month
    AND c.payout_debt_id IS NULL -- Prevent double-count if debt is active
    AND NOT EXISTS (
      SELECT 1 FROM public.gameya_installments i WHERE i.gameya_id = c.id
    );

  v_gameya := v_gameya_flex + v_gameya_legacy;

  RETURN GREATEST(v_real - v_commits - v_debts - v_gameya, 0);
END; $$;

REVOKE ALL ON FUNCTION public.fn_calculate_safe_to_spend(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_calculate_safe_to_spend(UUID) TO authenticated;
