-- =============================================================================
-- Mezan: 00025_fix_flexible_gameya_payout_ambiguous_transaction_id.sql
-- Phase 7C: Hotfix for ambiguous OUT parameter in gameya payout
-- =============================================================================

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
  
  IF v_debt_id IS NOT NULL THEN
    UPDATE public.gameya_circles gc SET status = 'RECEIVED_PAYING_DEBT' WHERE gc.id = p_gameya_id;
  ELSIF v_unpaid_installments = 0 THEN
    UPDATE public.gameya_circles gc SET status = 'COMPLETED' WHERE gc.id = p_gameya_id;
  END IF;

  transaction_id := v_turn_txn_id;
  RETURN NEXT;
  RETURN;
END; $$;

REVOKE ALL ON FUNCTION public.fn_receive_flexible_gameya_payout(UUID, UUID, UUID, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_receive_flexible_gameya_payout(UUID, UUID, UUID, TIMESTAMPTZ) TO authenticated;
