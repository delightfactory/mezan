-- =============================================================================
-- Mezan: 00026_flexible_gameya_exit_rpcs.sql
-- Phase 7D: Flexible Gameya Exit / Withdrawal RPCs
-- =============================================================================

-- 1. Schema Updates
ALTER TABLE public.gameya_circles 
ADD COLUMN IF NOT EXISTS payout_transaction_id UUID REFERENCES public.ledger_transactions(id),
ADD COLUMN IF NOT EXISTS payout_loan_transaction_id UUID REFERENCES public.ledger_transactions(id),
ADD COLUMN IF NOT EXISTS payout_debt_id UUID REFERENCES public.debts(id);

-- 2. Backfill Existing Payout Links
UPDATE public.gameya_circles gc
SET payout_transaction_id = gt.transaction_id
FROM public.gameya_turns gt
JOIN public.ledger_transactions lt ON lt.id = gt.transaction_id
WHERE gt.gameya_id = gc.id
  AND gt.status = 'RECEIVED'
  AND gt.transaction_id IS NOT NULL
  AND lt.type = 'GAMEYA_PAYOUT'
  AND gc.payout_transaction_id IS NULL;

-- 3. Update fn_receive_flexible_gameya_payout to populate new columns
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
  IF v_gameya.status != 'SAVING_PHASE' THEN RAISE EXCEPTION 'GAMEYA_NOT_ACTIVE'; END IF;
  
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
    ) RETURNING id INTO v_payout_txn_id;

    UPDATE public.wallets SET balance = balance - v_allocated_balance WHERE id = v_alloc_w.id;
    UPDATE public.wallets SET balance = balance + v_allocated_balance WHERE id = v_real_w.id;
    
    v_turn_txn_id := v_payout_txn_id;
  END IF;

  IF v_payout_amount > v_allocated_balance THEN
    v_gap := v_payout_amount - v_allocated_balance;
    
    INSERT INTO public.debts (
      family_id, entity_name, direction, original_amount, remaining_amount, created_by, status, due_date, monthly_installment
    ) VALUES (
      p_family_id, convert_from(decode('2KzZhdi52YrYqTog', 'base64'), 'UTF8') || v_gameya.name, 'BORROWED_FROM', v_gap, v_gap, v_m.id, 'ACTIVE', v_gameya.expected_payout_date, NULL
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

REVOKE ALL ON FUNCTION public.fn_receive_flexible_gameya_payout(UUID, UUID, UUID, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_receive_flexible_gameya_payout(UUID, UUID, UUID, TIMESTAMPTZ) TO authenticated;


-- 4. Create Central Exit RPC
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
  v_existing_debt public.debts;
  v_pay_amount NUMERIC(14,2);
BEGIN
  v_m := public._require_member(p_family_id);

  SELECT * INTO v_gameya FROM public.gameya_circles WHERE id = p_gameya_id AND family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAMEYA_NOT_FOUND'; END IF;
  IF v_gameya.status IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION 'GAMEYA_NOT_ACTIVE'; END IF;

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
    IF v_gameya.payout_transaction_id IS NULL AND v_gameya.payout_loan_transaction_id IS NULL THEN
      RAISE EXCEPTION 'GAMEYA_SETTLEMENT_REQUIRED';
    END IF;

    v_payout_received := 0;
    IF v_gameya.payout_transaction_id IS NOT NULL THEN
      v_payout_received := v_payout_received + (SELECT amount FROM public.ledger_transactions WHERE id = v_gameya.payout_transaction_id);
    END IF;
    IF v_gameya.payout_loan_transaction_id IS NOT NULL THEN
      v_payout_received := v_payout_received + (SELECT amount FROM public.ledger_transactions WHERE id = v_gameya.payout_loan_transaction_id);
    END IF;
    
    v_net_amount := v_payout_received - v_total_paid;

    IF v_net_amount > 0 THEN
      IF v_gameya.payout_debt_id IS NOT NULL THEN
        SELECT * INTO v_existing_debt FROM public.debts WHERE id = v_gameya.payout_debt_id AND family_id = p_family_id FOR UPDATE;
        v_net_amount := v_existing_debt.remaining_amount;
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
      END IF;

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

    ELSE
      IF p_settlement_mode != 'NOOP' THEN
        RAISE EXCEPTION 'GAMEYA_INVALID_SETTLEMENT_MODE';
      END IF;
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

REVOKE ALL ON FUNCTION public.fn_exit_flexible_gameya_circle(UUID, UUID, UUID, TEXT, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_exit_flexible_gameya_circle(UUID, UUID, UUID, TEXT, TIMESTAMPTZ) TO authenticated;
