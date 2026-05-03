-- =============================================================================
-- Mezan: 00027_existing_gameya_import.sql
-- Phase 8B: Existing Gameya Onboarding / Import Flow
-- =============================================================================

-- 1. fn_import_existing_gameya_circle
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
  v_txn_id UUID;
  v_debt_id UUID := NULL;
  v_due_date DATE;
  v_status TEXT;
  v_import_balance NUMERIC(14,2);
BEGIN
  v_m := public._require_member(p_family_id);

  IF p_installment_amount <= 0 THEN RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG'; END IF;
  IF p_total_turns <= 0 OR p_total_turns > 100 THEN RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG'; END IF;
  IF p_payout_turn < 1 OR p_payout_turn > p_total_turns THEN RAISE EXCEPTION 'GAMEYA_INVALID_PAYOUT_TURN'; END IF;
  IF p_paid_installments_count < 0 THEN RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG'; END IF;

  v_end_date := public._gameya_next_due_date(p_original_start_date, p_turn_frequency::text, p_total_turns - 1);
  v_expected_payout_date := public._gameya_payout_due_date(p_original_start_date, p_turn_frequency::text, p_payout_turn);
  v_installment_count := public._gameya_generate_installment_count(p_original_start_date, v_end_date, p_payment_frequency::text);
  
  IF v_installment_count > 500 THEN RAISE EXCEPTION 'GAMEYA_INVALID_CONFIG'; END IF;
  
  v_flex_payout_amount := p_installment_amount * v_installment_count;

  -- Create allocated wallet with initial 0 balance
  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (p_family_id, convert_from(decode('2LXZhtiv2YjZgiDYrNmF2LnZitipOiA=', 'base64'), 'UTF8') || p_name, 'ALLOCATED', 0, v_m.id)
  RETURNING id INTO v_wallet_id;

  -- Create OPENING_BALANCE ledger trace if there are paid installments
  v_import_balance := p_installment_amount * p_paid_installments_count;
  IF v_import_balance > 0 THEN
    INSERT INTO public.ledger_transactions(family_id, type, amount, to_wallet_id, description, effective_at, created_by) 
    VALUES(p_family_id, 'OPENING_BALANCE', v_import_balance, v_wallet_id, convert_from(decode('2LHYtdmK2K8g2LPYp9io2YIg2YTYrNmF2LnZitipOg==', 'base64'), 'UTF8') || p_name, p_effective_at, v_m.id) 
    RETURNING id INTO v_txn_id;

    UPDATE public.wallets SET balance = balance + v_import_balance WHERE id = v_wallet_id;
  END IF;

  -- Create gameya circle
  INSERT INTO public.gameya_circles (
    family_id, name, monthly_installment, total_months, payout_month, start_date, wallet_id, created_by,
    installment_amount, payment_frequency, turn_frequency, total_turns, payout_turn, expected_payout_date,
    flex_payout_amount, is_flexible, status
  ) VALUES (
    p_family_id, p_name, p_installment_amount, p_total_turns, p_payout_turn, p_original_start_date, v_wallet_id, v_m.id,
    p_installment_amount, p_payment_frequency, p_turn_frequency, p_total_turns, p_payout_turn, v_expected_payout_date,
    v_flex_payout_amount, true,
    CASE WHEN p_has_received_payout THEN 'RECEIVED_PAYING_DEBT'::public.gameya_status ELSE 'SAVING_PHASE'::public.gameya_status END
  ) RETURNING id INTO v_gameya_id;

  -- Handle Debt if payout received
  IF p_has_received_payout AND p_remaining_amount > 0 THEN
    INSERT INTO public.debts (
      family_id, entity_name, direction, original_amount, remaining_amount, created_by, status, due_date, monthly_installment
    ) VALUES (
      p_family_id, convert_from(decode('2KzZhdi52YrYqTog', 'base64'), 'UTF8') || p_name, 'BORROWED_FROM', p_remaining_amount, p_remaining_amount, v_m.id, 'ACTIVE', v_expected_payout_date, p_installment_amount
    ) RETURNING id INTO v_debt_id;

    UPDATE public.gameya_circles SET payout_debt_id = v_debt_id WHERE id = v_gameya_id;
  END IF;

  -- Generate Turns
  FOR v_i IN 1..p_total_turns LOOP
    v_due_date := public._gameya_next_due_date(p_original_start_date, p_turn_frequency::text, v_i - 1);
    v_status := 'UPCOMING';
    IF p_has_received_payout AND v_i = p_payout_turn THEN
        v_status := 'RECEIVED';
    END IF;
    INSERT INTO public.gameya_turns (
      gameya_id, family_id, turn_number, due_date, status
    ) VALUES (
      v_gameya_id, p_family_id, v_i, v_due_date, v_status::public.gameya_turn_status
    );
  END LOOP;

  -- Generate Installments
  FOR v_i IN 1..v_installment_count LOOP
    v_due_date := public._gameya_next_due_date(p_original_start_date, p_payment_frequency::text, v_i - 1);
    
    IF v_i <= p_paid_installments_count THEN
        -- Past paid installment
        INSERT INTO public.gameya_installments (
          gameya_id, family_id, installment_number, due_date, amount, status, transaction_id, paid_at
        ) VALUES (
          v_gameya_id, p_family_id, v_i, v_due_date, p_installment_amount, 'PAID', v_txn_id, p_effective_at
        );
    ELSIF p_has_received_payout THEN
        -- Double count prevention: if payout received, remaining installments are handled by debt
        INSERT INTO public.gameya_installments (
          gameya_id, family_id, installment_number, due_date, amount, status
        ) VALUES (
          v_gameya_id, p_family_id, v_i, v_due_date, p_installment_amount, 'CANCELLED'
        );
    ELSE
        -- Not paid yet
        v_status := CASE WHEN v_due_date < p_tracking_start_date THEN 'OVERDUE' ELSE 'UPCOMING' END;
        INSERT INTO public.gameya_installments (
          gameya_id, family_id, installment_number, due_date, amount, status
        ) VALUES (
          v_gameya_id, p_family_id, v_i, v_due_date, p_installment_amount, v_status::public.occurrence_status
        );
    END IF;
  END LOOP;

  RETURN v_gameya_id;
END; $$;

-- 2. Grants
REVOKE ALL ON FUNCTION public.fn_import_existing_gameya_circle(UUID, TEXT, NUMERIC, public.gameya_payment_frequency, public.gameya_turn_frequency, INT, INT, DATE, DATE, INT, BOOLEAN, NUMERIC, NUMERIC, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_import_existing_gameya_circle(UUID, TEXT, NUMERIC, public.gameya_payment_frequency, public.gameya_turn_frequency, INT, INT, DATE, DATE, INT, BOOLEAN, NUMERIC, NUMERIC, TIMESTAMPTZ) TO authenticated;
