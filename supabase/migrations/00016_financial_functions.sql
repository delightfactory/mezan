-- Mezan: 00016_financial_functions.sql — Atomic RPCs
-- Internal helper
CREATE OR REPLACE FUNCTION public._require_member(p_family_id UUID, p_roles public.member_role[] DEFAULT ARRAY['OWNER','MEMBER']::public.member_role[])
RETURNS public.family_members LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members;
BEGIN
  SELECT * INTO v_m FROM public.family_members WHERE user_id=auth.uid() AND family_id=p_family_id AND status='ACTIVE' AND role=ANY(p_roles);
  IF NOT FOUND THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
  RETURN v_m;
END; $$;

REVOKE ALL ON FUNCTION public._require_member(UUID, public.member_role[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._require_member(UUID, public.member_role[]) FROM anon;
GRANT EXECUTE ON FUNCTION public._require_member(UUID, public.member_role[]) TO authenticated;

-- 1. Record Income
CREATE OR REPLACE FUNCTION public.fn_record_income(p_family_id UUID, p_amount NUMERIC(14,2), p_to_wallet_id UUID, p_category_id UUID, p_description TEXT DEFAULT NULL, p_effective_at TIMESTAMPTZ DEFAULT now(), p_notes TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_w public.wallets; v_id UUID;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.categories WHERE id = p_category_id AND direction = 'INCOME' AND (family_id IS NULL OR family_id = p_family_id) AND NOT is_archived) THEN
    RAISE EXCEPTION 'INVALID_CATEGORY_DIRECTION';
  END IF;
  SELECT * INTO v_w FROM public.wallets WHERE id=p_to_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  INSERT INTO public.ledger_transactions(family_id,type,amount,to_wallet_id,category_id,description,effective_at,created_by,notes) VALUES(p_family_id,'INCOME',p_amount,p_to_wallet_id,p_category_id,p_description,p_effective_at,v_m.id,p_notes) RETURNING id INTO v_id;
  UPDATE public.wallets SET balance=balance+p_amount WHERE id=p_to_wallet_id;
  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) VALUES(p_family_id,'TRANSACTION_CREATED',v_m.id,'transaction',v_id,jsonb_build_object('type','INCOME','amount',p_amount));
  RETURN v_id;
END; $$;

-- 2. Record Expense
CREATE OR REPLACE FUNCTION public.fn_record_expense(p_family_id UUID, p_amount NUMERIC(14,2), p_from_wallet_id UUID, p_category_id UUID, p_description TEXT DEFAULT NULL, p_effective_at TIMESTAMPTZ DEFAULT now(), p_notes TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_w public.wallets; v_id UUID;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.categories WHERE id = p_category_id AND direction = 'EXPENSE' AND (family_id IS NULL OR family_id = p_family_id) AND NOT is_archived) THEN
    RAISE EXCEPTION 'INVALID_CATEGORY_DIRECTION';
  END IF;
  SELECT * INTO v_w FROM public.wallets WHERE id=p_from_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  IF v_w.balance < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;
  INSERT INTO public.ledger_transactions(family_id,type,amount,from_wallet_id,category_id,description,effective_at,created_by,notes) VALUES(p_family_id,'EXPENSE',p_amount,p_from_wallet_id,p_category_id,p_description,p_effective_at,v_m.id,p_notes) RETURNING id INTO v_id;
  UPDATE public.wallets SET balance=balance-p_amount WHERE id=p_from_wallet_id;
  UPDATE public.budgets SET spent_amount=spent_amount+p_amount WHERE family_id=p_family_id AND category_id=p_category_id AND p_effective_at::date BETWEEN cycle_start AND cycle_end;
  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) VALUES(p_family_id,'TRANSACTION_CREATED',v_m.id,'transaction',v_id,jsonb_build_object('type','EXPENSE','amount',p_amount));
  RETURN v_id;
END; $$;

-- 3. Transfer Between Wallets (deterministic lock order)
CREATE OR REPLACE FUNCTION public.fn_transfer_between_wallets(p_family_id UUID, p_amount NUMERIC(14,2), p_from_wallet_id UUID, p_to_wallet_id UUID, p_category_id UUID DEFAULT NULL, p_description TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_fw public.wallets; v_tw public.wallets; v_id UUID;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF p_from_wallet_id = p_to_wallet_id THEN RAISE EXCEPTION 'SAME_WALLET'; END IF;
  -- Deterministic lock order by UUID to prevent deadlocks
  IF p_from_wallet_id < p_to_wallet_id THEN
    SELECT * INTO v_fw FROM public.wallets WHERE id=p_from_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
    SELECT * INTO v_tw FROM public.wallets WHERE id=p_to_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
  ELSE
    SELECT * INTO v_tw FROM public.wallets WHERE id=p_to_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
    SELECT * INTO v_fw FROM public.wallets WHERE id=p_from_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
  END IF;
  IF v_fw IS NULL THEN RAISE EXCEPTION 'SOURCE_WALLET_NOT_FOUND'; END IF;
  IF v_tw IS NULL THEN RAISE EXCEPTION 'DEST_WALLET_NOT_FOUND'; END IF;
  IF v_fw.balance < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;
  INSERT INTO public.ledger_transactions(family_id,type,amount,from_wallet_id,to_wallet_id,category_id,description,created_by) VALUES(p_family_id,'TRANSFER',p_amount,p_from_wallet_id,p_to_wallet_id,p_category_id,p_description,v_m.id) RETURNING id INTO v_id;
  UPDATE public.wallets SET balance=balance-p_amount WHERE id=p_from_wallet_id;
  UPDATE public.wallets SET balance=balance+p_amount WHERE id=p_to_wallet_id;
  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) VALUES(p_family_id,'TRANSACTION_CREATED',v_m.id,'transaction',v_id,jsonb_build_object('type','TRANSFER','amount',p_amount));
  RETURN v_id;
END; $$;

-- 4. Correct Transaction (reversal + optional adjustment)
CREATE OR REPLACE FUNCTION public.fn_correct_transaction(p_family_id UUID, p_original_txn_id UUID, p_new_amount NUMERIC(14,2) DEFAULT NULL, p_new_category_id UUID DEFAULT NULL, p_new_description TEXT DEFAULT NULL, p_new_effective_at TIMESTAMPTZ DEFAULT NULL)
RETURNS TABLE(reversal_id UUID, adjustment_id UUID) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_o public.ledger_transactions; v_rev UUID; v_adj UUID:=NULL; v_adj_effective_at TIMESTAMPTZ;
BEGIN
  v_m := public._require_member(p_family_id);
  SELECT * INTO v_o FROM public.ledger_transactions WHERE id=p_original_txn_id AND family_id=p_family_id AND status='POSTED' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TXN_NOT_FOUND'; END IF;
  
  -- Restrict correction to simple types for MVP
  IF v_o.type NOT IN ('INCOME', 'EXPENSE', 'TRANSFER') THEN
    RAISE EXCEPTION 'CORRECTION_NOT_ALLOWED: Can only correct INCOME, EXPENSE, or TRANSFER. Complex transactions must be corrected via specific flows.';
  END IF;
  -- Lock wallets deterministically
  IF v_o.from_wallet_id IS NOT NULL AND v_o.to_wallet_id IS NOT NULL THEN
    IF v_o.from_wallet_id < v_o.to_wallet_id THEN
      PERFORM id FROM public.wallets WHERE id=v_o.from_wallet_id FOR UPDATE;
      PERFORM id FROM public.wallets WHERE id=v_o.to_wallet_id FOR UPDATE;
    ELSE
      PERFORM id FROM public.wallets WHERE id=v_o.to_wallet_id FOR UPDATE;
      PERFORM id FROM public.wallets WHERE id=v_o.from_wallet_id FOR UPDATE;
    END IF;
  ELSIF v_o.from_wallet_id IS NOT NULL THEN PERFORM id FROM public.wallets WHERE id=v_o.from_wallet_id FOR UPDATE;
  ELSIF v_o.to_wallet_id IS NOT NULL THEN PERFORM id FROM public.wallets WHERE id=v_o.to_wallet_id FOR UPDATE;
  END IF;
  -- Mark original REVERSED
  UPDATE public.ledger_transactions SET status='REVERSED' WHERE id=p_original_txn_id;
  -- Create reversal
  INSERT INTO public.ledger_transactions(family_id,type,status,amount,from_wallet_id,to_wallet_id,category_id,description,created_by) VALUES(p_family_id,'REVERSAL','POSTED',v_o.amount,v_o.to_wallet_id,v_o.from_wallet_id,v_o.category_id,'تصحيح حركة',v_m.id) RETURNING id INTO v_rev;
  IF v_o.from_wallet_id IS NOT NULL THEN UPDATE public.wallets SET balance=balance+v_o.amount WHERE id=v_o.from_wallet_id; END IF;
  IF v_o.to_wallet_id IS NOT NULL THEN UPDATE public.wallets SET balance=balance-v_o.amount WHERE id=v_o.to_wallet_id; END IF;
  IF v_o.type='EXPENSE' THEN UPDATE public.budgets SET spent_amount=GREATEST(0,spent_amount-v_o.amount) WHERE family_id=p_family_id AND category_id=v_o.category_id AND v_o.effective_at::date BETWEEN cycle_start AND cycle_end; END IF;
  INSERT INTO public.transaction_links(family_id,source_transaction_id,related_transaction_id,link_type) VALUES(p_family_id,p_original_txn_id,v_rev,'REVERSAL');
  
  -- Optional adjustment (same type as original)
  IF p_new_amount IS NOT NULL AND p_new_amount > 0 THEN
    v_adj_effective_at := COALESCE(p_new_effective_at, v_o.effective_at);
    INSERT INTO public.ledger_transactions(family_id,type,status,amount,from_wallet_id,to_wallet_id,category_id,description,created_by,effective_at) VALUES(p_family_id,v_o.type,'POSTED',p_new_amount,v_o.from_wallet_id,v_o.to_wallet_id,COALESCE(p_new_category_id,v_o.category_id),COALESCE(p_new_description,v_o.description),v_m.id,v_adj_effective_at) RETURNING id INTO v_adj;
    IF v_o.from_wallet_id IS NOT NULL THEN UPDATE public.wallets SET balance=balance-p_new_amount WHERE id=v_o.from_wallet_id; END IF;
    IF v_o.to_wallet_id IS NOT NULL THEN UPDATE public.wallets SET balance=balance+p_new_amount WHERE id=v_o.to_wallet_id; END IF;
    IF v_o.type='EXPENSE' THEN UPDATE public.budgets SET spent_amount=spent_amount+p_new_amount WHERE family_id=p_family_id AND category_id=COALESCE(p_new_category_id,v_o.category_id) AND v_adj_effective_at::date BETWEEN cycle_start AND cycle_end; END IF;
    INSERT INTO public.transaction_links(family_id,source_transaction_id,related_transaction_id,link_type) VALUES(p_family_id,p_original_txn_id,v_adj,'ADJUSTMENT');
  END IF;
  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) VALUES(p_family_id,'TRANSACTION_REVERSED',v_m.id,'transaction',p_original_txn_id,jsonb_build_object('reversal_id',v_rev,'adjustment_id',v_adj));
  RETURN QUERY SELECT v_rev, v_adj;
END; $$;

-- 5. Receive Gameya Payout (atomic: ledger transfer from reserve + create debt)
DROP FUNCTION IF EXISTS public.fn_receive_gameya_payout(UUID, UUID, UUID);
CREATE OR REPLACE FUNCTION public.fn_receive_gameya_payout(p_family_id UUID, p_gameya_id UUID, p_real_wallet_id UUID)
RETURNS TABLE(reserve_transfer_txn_id UUID, loan_receive_txn_id UUID) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_g public.gameya_circles; v_alloc_w public.wallets; v_real_w public.wallets; v_paid NUMERIC(14,2); v_rem NUMERIC(14,2); v_id UUID := NULL; v_loan_id UUID := NULL; v_did UUID;
BEGIN
  v_m := public._require_member(p_family_id);
  SELECT * INTO v_g FROM public.gameya_circles WHERE id=p_gameya_id AND family_id=p_family_id AND status='SAVING_PHASE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAMEYA_NOT_FOUND'; END IF;
  -- Lock wallets deterministically
  IF v_g.wallet_id < p_real_wallet_id THEN
    SELECT * INTO v_alloc_w FROM public.wallets WHERE id=v_g.wallet_id FOR UPDATE;
    SELECT * INTO v_real_w FROM public.wallets WHERE id=p_real_wallet_id AND family_id=p_family_id FOR UPDATE;
  ELSE
    SELECT * INTO v_real_w FROM public.wallets WHERE id=p_real_wallet_id AND family_id=p_family_id FOR UPDATE;
    SELECT * INTO v_alloc_w FROM public.wallets WHERE id=v_g.wallet_id FOR UPDATE;
  END IF;
  IF v_alloc_w IS NULL OR v_real_w IS NULL THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;

  -- True paid so far comes from the allocated reserve wallet balance
  v_paid := LEAST(v_alloc_w.balance, v_g.payout_amount);
  
  IF v_alloc_w.balance > v_g.payout_amount THEN
    RAISE EXCEPTION 'GAMEYA_RESERVE_OVERFUNDED';
  END IF;

  v_rem := v_g.payout_amount - v_paid;
  IF v_paid > 0 THEN
    INSERT INTO public.ledger_transactions(family_id,type,amount,from_wallet_id,to_wallet_id,description,created_by) 
    VALUES(p_family_id,'GAMEYA_PAYOUT',v_paid,v_g.wallet_id,p_real_wallet_id,'تصفية رصيد جمعية: '||v_g.name,v_m.id) RETURNING id INTO v_id;
    
    UPDATE public.wallets SET balance=balance-v_paid WHERE id=v_g.wallet_id;
    UPDATE public.wallets SET balance=balance+v_paid WHERE id=p_real_wallet_id;
  END IF;

  -- 2. If there's remaining (early payout), it's a loan injection
  IF v_rem > 0 THEN
    -- We receive the rest from outside as a debt
    INSERT INTO public.ledger_transactions(family_id,type,amount,to_wallet_id,description,created_by) 
    VALUES(p_family_id,'LOAN_RECEIVE',v_rem,p_real_wallet_id,'استلام متبقي جمعية مبكرة: '||v_g.name,v_m.id) RETURNING id INTO v_loan_id;
    
    UPDATE public.wallets SET balance=balance+v_rem WHERE id=p_real_wallet_id;
    
    INSERT INTO public.debts(family_id,entity_name,direction,original_amount,remaining_amount,monthly_installment,status,notes,created_by) 
    VALUES(p_family_id,'جمعية: '||v_g.name,'BORROWED_FROM',v_rem,v_rem,v_g.monthly_installment,'ACTIVE','دين جمعية مبكر',v_m.id) RETURNING id INTO v_did;
    
    INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) 
    VALUES(p_family_id,'DEBT_CREATED',v_m.id,'debt',v_did,jsonb_build_object('source','gameya','amount',v_rem));
  END IF;
  
  UPDATE public.gameya_circles SET status='RECEIVED_PAYING_DEBT' WHERE id=p_gameya_id;
  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) 
  VALUES(p_family_id,'GAMEYA_PAYOUT_RECEIVED',v_m.id,'gameya',p_gameya_id,jsonb_build_object('payout',v_g.payout_amount,'paid',v_paid,'debt',v_rem,'reserve_transfer_txn_id',v_id,'loan_receive_txn_id',v_loan_id));
  
  RETURN QUERY SELECT v_id, v_loan_id;
END; $$;

-- 6. Record Debt Payment (handles both BORROWED_FROM and LENT_TO)
CREATE OR REPLACE FUNCTION public.fn_record_debt_payment(p_family_id UUID, p_debt_id UUID, p_amount NUMERIC(14,2), p_wallet_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_d public.debts; v_w public.wallets; v_id UUID; v_tt public.txn_type;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  SELECT * INTO v_d FROM public.debts WHERE id=p_debt_id AND family_id=p_family_id AND status='ACTIVE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DEBT_NOT_FOUND'; END IF;
  IF p_amount > v_d.remaining_amount THEN RAISE EXCEPTION 'OVERPAYMENT'; END IF;
  SELECT * INTO v_w FROM public.wallets WHERE id=p_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  
  IF v_d.direction = 'BORROWED_FROM' THEN
    -- We are paying someone -> money leaves wallet
    IF v_w.balance < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;
    INSERT INTO public.ledger_transactions(family_id,type,amount,from_wallet_id,description,created_by) VALUES(p_family_id,'LOAN_PAYMENT_OUT',p_amount,p_wallet_id,'سداد دين: '||v_d.entity_name,v_m.id) RETURNING id INTO v_id;
    UPDATE public.wallets SET balance=balance-p_amount WHERE id=p_wallet_id;
  ELSE
    -- Someone is paying us -> money enters wallet
    INSERT INTO public.ledger_transactions(family_id,type,amount,to_wallet_id,description,created_by) VALUES(p_family_id,'LOAN_PAYMENT_IN',p_amount,p_wallet_id,'تحصيل دين: '||v_d.entity_name,v_m.id) RETURNING id INTO v_id;
    UPDATE public.wallets SET balance=balance+p_amount WHERE id=p_wallet_id;
  END IF;

  UPDATE public.debts SET remaining_amount=remaining_amount-p_amount, status=CASE WHEN remaining_amount-p_amount=0 THEN 'SETTLED'::public.debt_status ELSE status END WHERE id=p_debt_id;
  INSERT INTO public.debt_payments(debt_id,family_id,amount,transaction_id) VALUES(p_debt_id,p_family_id,p_amount,v_id);
  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) VALUES(p_family_id,'DEBT_PAYMENT',v_m.id,'debt',p_debt_id,jsonb_build_object('amount',p_amount));
  RETURN v_id;
END; $$;

-- 7. Safe-to-Spend (read-only)
CREATE OR REPLACE FUNCTION public.fn_calculate_safe_to_spend(p_family_id UUID)
RETURNS NUMERIC(14,2) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_real NUMERIC(14,2); v_alloc NUMERIC(14,2); v_commits NUMERIC(14,2);
BEGIN
  PERFORM public._require_member(p_family_id, ARRAY['OWNER','MEMBER','VIEWER']::public.member_role[]);
  SELECT COALESCE(SUM(balance),0) INTO v_real FROM public.wallets WHERE family_id=p_family_id AND type='REAL' AND NOT is_archived;
  SELECT COALESCE(SUM(balance),0) INTO v_alloc FROM public.wallets WHERE family_id=p_family_id AND type='ALLOCATED' AND NOT is_archived;
  SELECT COALESCE(SUM(amount),0) INTO v_commits FROM public.commitment_occurrences WHERE family_id=p_family_id AND status IN ('UPCOMING','OVERDUE');
  RETURN GREATEST(v_real - v_alloc - v_commits, 0);
END; $$;

-- 8. Reconciliation
CREATE OR REPLACE FUNCTION public.fn_recalculate_wallet_balance(p_wallet_id UUID)
RETURNS NUMERIC(14,2) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_w public.wallets; v_c NUMERIC(14,2);
BEGIN
  SELECT * INTO v_w FROM public.wallets WHERE id=p_wallet_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  PERFORM public._require_member(v_w.family_id, ARRAY['OWNER']::public.member_role[]);
  SELECT COALESCE(SUM(CASE WHEN to_wallet_id=p_wallet_id THEN amount ELSE 0 END),0) - COALESCE(SUM(CASE WHEN from_wallet_id=p_wallet_id THEN amount ELSE 0 END),0) INTO v_c FROM public.ledger_transactions WHERE (from_wallet_id=p_wallet_id OR to_wallet_id=p_wallet_id) AND status IN ('POSTED', 'REVERSED');
  UPDATE public.wallets SET balance=v_c WHERE id=p_wallet_id;
  RETURN v_c;
END; $$;

-- 9. Record Opening Balance
CREATE OR REPLACE FUNCTION public.fn_record_opening_balance(p_family_id UUID, p_wallet_id UUID, p_amount NUMERIC(14,2), p_effective_at TIMESTAMPTZ DEFAULT now())
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_w public.wallets; v_id UUID;
BEGIN
  v_m := public._require_member(p_family_id, ARRAY['OWNER']::public.member_role[]);
  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  SELECT * INTO v_w FROM public.wallets WHERE id=p_wallet_id AND family_id=p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  IF v_w.balance != 0 THEN RAISE EXCEPTION 'WALLET_NOT_EMPTY'; END IF;
  
  INSERT INTO public.ledger_transactions(family_id,type,amount,to_wallet_id,description,effective_at,created_by) 
  VALUES(p_family_id,'OPENING_BALANCE',p_amount,p_wallet_id,'رصيد افتتاحي',p_effective_at,v_m.id) RETURNING id INTO v_id;
  
  UPDATE public.wallets SET balance=balance+p_amount WHERE id=p_wallet_id;
  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) 
  VALUES(p_family_id,'TRANSACTION_CREATED',v_m.id,'transaction',v_id,jsonb_build_object('type','OPENING_BALANCE','amount',p_amount));
  RETURN v_id;
END; $$;

-- 10. Record Gameya Installment
CREATE OR REPLACE FUNCTION public.fn_record_gameya_installment(p_family_id UUID, p_turn_id UUID, p_real_wallet_id UUID, p_effective_at TIMESTAMPTZ DEFAULT now())
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_g public.gameya_circles; v_t public.gameya_turns; v_alloc_w public.wallets; v_real_w public.wallets; v_id UUID;
BEGIN
  v_m := public._require_member(p_family_id);
  
  -- Lock turn
  SELECT * INTO v_t FROM public.gameya_turns WHERE id=p_turn_id AND family_id=p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAMEYA_TURN_NOT_FOUND'; END IF;
  IF v_t.status != 'UPCOMING' THEN RAISE EXCEPTION 'GAMEYA_TURN_ALREADY_PAID'; END IF;

  -- Lock gameya
  SELECT * INTO v_g FROM public.gameya_circles WHERE id=v_t.gameya_id AND family_id=p_family_id AND status='SAVING_PHASE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GAMEYA_NOT_FOUND_OR_NOT_IN_SAVING_PHASE'; END IF;
  
  IF v_g.wallet_id < p_real_wallet_id THEN
    SELECT * INTO v_alloc_w FROM public.wallets WHERE id=v_g.wallet_id FOR UPDATE;
    SELECT * INTO v_real_w FROM public.wallets WHERE id=p_real_wallet_id AND family_id=p_family_id AND type='REAL' FOR UPDATE;
  ELSE
    SELECT * INTO v_real_w FROM public.wallets WHERE id=p_real_wallet_id AND family_id=p_family_id AND type='REAL' FOR UPDATE;
    SELECT * INTO v_alloc_w FROM public.wallets WHERE id=v_g.wallet_id FOR UPDATE;
  END IF;
  
  IF v_alloc_w IS NULL OR v_real_w IS NULL THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  IF v_real_w.balance < v_g.monthly_installment THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;

  INSERT INTO public.ledger_transactions(family_id,type,amount,from_wallet_id,to_wallet_id,description,effective_at,created_by) 
  VALUES(p_family_id,'GAMEYA_INSTALLMENT',v_g.monthly_installment,p_real_wallet_id,v_g.wallet_id,'دفع قسط جمعية: '||v_g.name||' (شهر '||v_t.turn_number||')',p_effective_at,v_m.id) RETURNING id INTO v_id;
  
  UPDATE public.wallets SET balance=balance-v_g.monthly_installment WHERE id=p_real_wallet_id;
  UPDATE public.wallets SET balance=balance+v_g.monthly_installment WHERE id=v_g.wallet_id;
  
  UPDATE public.gameya_turns SET status='PAID', transaction_id=v_id, paid_at=now() WHERE id=p_turn_id;

  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) 
  VALUES(p_family_id,'GAMEYA_INSTALLMENT_PAID',v_m.id,'transaction',v_id,jsonb_build_object('turn_id',p_turn_id,'gameya_id',v_t.gameya_id,'amount',v_g.monthly_installment));
  RETURN v_id;
END; $$;

-- 11. Disburse Loan (LENT_TO)
CREATE OR REPLACE FUNCTION public.fn_disburse_loan(p_family_id UUID, p_entity_name TEXT, p_amount NUMERIC(14,2), p_wallet_id UUID, p_effective_at TIMESTAMPTZ DEFAULT now())
RETURNS TABLE(debt_id UUID, transaction_id UUID) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_w public.wallets; v_did UUID; v_tid UUID;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  SELECT * INTO v_w FROM public.wallets WHERE id=p_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;
  IF v_w.balance < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_BALANCE'; END IF;

  INSERT INTO public.debts(family_id,entity_name,direction,original_amount,remaining_amount,status,created_by) 
  VALUES(p_family_id,p_entity_name,'LENT_TO',p_amount,p_amount,'ACTIVE',v_m.id) RETURNING id INTO v_did;

  INSERT INTO public.ledger_transactions(family_id,type,amount,from_wallet_id,description,effective_at,created_by) 
  VALUES(p_family_id,'LOAN_DISBURSE',p_amount,p_wallet_id,'إقراض: '||p_entity_name,p_effective_at,v_m.id) RETURNING id INTO v_tid;
  
  UPDATE public.wallets SET balance=balance-p_amount WHERE id=p_wallet_id;
  
  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) 
  VALUES(p_family_id,'DEBT_CREATED',v_m.id,'debt',v_did,jsonb_build_object('type','LENT_TO','amount',p_amount,'transaction_id',v_tid));
  
  RETURN QUERY SELECT v_did, v_tid;
END; $$;

-- 12. Receive Loan (BORROWED_FROM)
CREATE OR REPLACE FUNCTION public.fn_receive_loan(p_family_id UUID, p_entity_name TEXT, p_amount NUMERIC(14,2), p_wallet_id UUID, p_effective_at TIMESTAMPTZ DEFAULT now())
RETURNS TABLE(debt_id UUID, transaction_id UUID) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m public.family_members; v_w public.wallets; v_did UUID; v_tid UUID;
BEGIN
  v_m := public._require_member(p_family_id);
  IF p_amount <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  SELECT * INTO v_w FROM public.wallets WHERE id=p_wallet_id AND family_id=p_family_id AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_NOT_FOUND'; END IF;

  INSERT INTO public.debts(family_id,entity_name,direction,original_amount,remaining_amount,status,created_by) 
  VALUES(p_family_id,p_entity_name,'BORROWED_FROM',p_amount,p_amount,'ACTIVE',v_m.id) RETURNING id INTO v_did;

  INSERT INTO public.ledger_transactions(family_id,type,amount,to_wallet_id,description,effective_at,created_by) 
  VALUES(p_family_id,'LOAN_RECEIVE',p_amount,p_wallet_id,'استدانة من: '||p_entity_name,p_effective_at,v_m.id) RETURNING id INTO v_tid;
  
  UPDATE public.wallets SET balance=balance+p_amount WHERE id=p_wallet_id;
  
  INSERT INTO public.audit_events(family_id,action,actor_id,target_type,target_id,details) 
  VALUES(p_family_id,'DEBT_CREATED',v_m.id,'debt',v_did,jsonb_build_object('type','BORROWED_FROM','amount',p_amount,'transaction_id',v_tid));
  
  RETURN QUERY SELECT v_did, v_tid;
END; $$;

-- Grants
REVOKE ALL ON FUNCTION public.fn_record_income(UUID, NUMERIC, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_record_income(UUID, NUMERIC, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_record_expense(UUID, NUMERIC, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_record_expense(UUID, NUMERIC, UUID, UUID, TEXT, TIMESTAMPTZ, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_transfer_between_wallets(UUID, NUMERIC, UUID, UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_transfer_between_wallets(UUID, NUMERIC, UUID, UUID, UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_correct_transaction(UUID, UUID, NUMERIC, UUID, TEXT, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_correct_transaction(UUID, UUID, NUMERIC, UUID, TEXT, TIMESTAMPTZ) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_receive_gameya_payout(UUID, UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_receive_gameya_payout(UUID, UUID, UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_record_debt_payment(UUID, UUID, NUMERIC, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_record_debt_payment(UUID, UUID, NUMERIC, UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_calculate_safe_to_spend(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_calculate_safe_to_spend(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_recalculate_wallet_balance(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_recalculate_wallet_balance(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_record_opening_balance(UUID, UUID, NUMERIC, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_record_opening_balance(UUID, UUID, NUMERIC, TIMESTAMPTZ) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_record_gameya_installment(UUID, UUID, UUID, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_record_gameya_installment(UUID, UUID, UUID, TIMESTAMPTZ) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_disburse_loan(UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_disburse_loan(UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_receive_loan(UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_receive_loan(UUID, TEXT, NUMERIC, UUID, TIMESTAMPTZ) TO authenticated;
