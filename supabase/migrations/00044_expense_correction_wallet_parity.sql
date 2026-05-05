-- Mezan: 00044_expense_correction_wallet_parity.sql

-- 1. Redefine fn_correct_expense_transaction to allow ALLOCATED wallets
-- and allow the original wallet to be archived.
CREATE OR REPLACE FUNCTION public.fn_correct_expense_transaction(
    p_family_id uuid,
    p_original_txn_id uuid,
    p_new_amount numeric(14,2),
    p_new_from_wallet_id uuid,
    p_new_category_id uuid,
    p_new_description text DEFAULT NULL,
    p_new_effective_at timestamptz DEFAULT NULL,
    p_new_notes text DEFAULT NULL,
    p_receipt_mode text DEFAULT 'KEEP_ON_ORIGINAL' -- 'KEEP_ON_ORIGINAL', 'COPY_TO_ADJUSTMENT', 'MOVE_TO_ADJUSTMENT'
) RETURNS TABLE (
    reversal_id uuid,
    adjustment_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_member public.family_members;
    v_orig_txn public.ledger_transactions;
    v_new_cat public.categories;
    v_reversal_id uuid;
    v_adj_id uuid;
    v_eff_at timestamptz;
    v_first_wallet uuid;
    v_second_wallet uuid;
    v_w1 public.wallets;
    v_w2 public.wallets;
    v_new_wallet_balance numeric;
    v_orig_att public.transaction_attachments;
    v_new_att_id uuid;
BEGIN
    -- 1. Member Verification
    SELECT * INTO v_member FROM public._require_member(p_family_id, ARRAY['OWNER', 'MEMBER']::public.member_role[]);

    IF p_new_amount <= 0 THEN
        RAISE EXCEPTION 'New amount must be positive';
    END IF;

    IF p_receipt_mode NOT IN ('KEEP_ON_ORIGINAL', 'COPY_TO_ADJUSTMENT', 'MOVE_TO_ADJUSTMENT') THEN
        RAISE EXCEPTION 'INVALID_RECEIPT_MODE';
    END IF;

    -- 2. Lock original transaction
    SELECT * INTO v_orig_txn FROM public.ledger_transactions
    WHERE id = p_original_txn_id
      AND family_id = p_family_id
      AND type = 'EXPENSE'
      AND status = 'POSTED'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Original posted expense transaction not found';
    END IF;

    -- Verify new category
    SELECT * INTO v_new_cat FROM public.categories
    WHERE id = p_new_category_id AND (family_id = p_family_id OR is_system = true) AND direction = 'EXPENSE' AND is_archived = false;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid new category';
    END IF;

    v_eff_at := COALESCE(p_new_effective_at, v_orig_txn.effective_at);

    -- Lock wallets deterministically
    IF v_orig_txn.from_wallet_id < p_new_from_wallet_id THEN
        v_first_wallet := v_orig_txn.from_wallet_id;
        v_second_wallet := p_new_from_wallet_id;
    ELSE
        v_first_wallet := p_new_from_wallet_id;
        v_second_wallet := v_orig_txn.from_wallet_id;
    END IF;

    -- Lock first wallet
    SELECT * INTO v_w1 FROM public.wallets WHERE id = v_first_wallet AND family_id = p_family_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'WALLET_NOT_FOUND';
    END IF;
    -- Verify if first wallet is the NEW wallet
    IF v_first_wallet = p_new_from_wallet_id THEN
        IF v_w1.is_archived = true OR v_w1.type NOT IN ('REAL', 'ALLOCATED') THEN
            RAISE EXCEPTION 'INVALID_NEW_WALLET';
        END IF;
    END IF;

    -- Lock second wallet (if different)
    IF v_first_wallet != v_second_wallet THEN
        SELECT * INTO v_w2 FROM public.wallets WHERE id = v_second_wallet AND family_id = p_family_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'WALLET_NOT_FOUND';
        END IF;
        -- Verify if second wallet is the NEW wallet
        IF v_second_wallet = p_new_from_wallet_id THEN
            IF v_w2.is_archived = true OR v_w2.type NOT IN ('REAL', 'ALLOCATED') THEN
                RAISE EXCEPTION 'INVALID_NEW_WALLET';
            END IF;
        END IF;
    END IF;

    -- 3. Reverse the original
    UPDATE public.ledger_transactions
    SET status = 'REVERSED', metadata = jsonb_set(metadata, '{reversed_by}', to_jsonb(v_member.id))
    WHERE id = p_original_txn_id;

    INSERT INTO public.ledger_transactions (
        family_id, type, amount, from_wallet_id, to_wallet_id,
        category_id, status, created_by, effective_at, description, notes, metadata
    ) VALUES (
        p_family_id, 'REVERSAL', v_orig_txn.amount, v_orig_txn.to_wallet_id, v_orig_txn.from_wallet_id,
        v_orig_txn.category_id, 'POSTED', v_member.id, now(),
        'عكس تلقائي لعملية مصروف ' || COALESCE(v_orig_txn.description, ''),
        'Reversal of ' || p_original_txn_id,
        jsonb_build_object('original_transaction_id', p_original_txn_id)
    ) RETURNING id INTO v_reversal_id;

    INSERT INTO public.transaction_links (family_id, source_transaction_id, related_transaction_id, link_type)
    VALUES (p_family_id, p_original_txn_id, v_reversal_id, 'REVERSAL');

    -- Restore old wallet balance
    UPDATE public.wallets
    SET balance = balance + v_orig_txn.amount, updated_at = now()
    WHERE id = v_orig_txn.from_wallet_id;

    -- Deduct from old budget
    UPDATE public.budgets
    SET spent_amount = GREATEST(0, spent_amount - v_orig_txn.amount), updated_at = now()
    WHERE family_id = p_family_id
      AND category_id = v_orig_txn.category_id
      AND v_orig_txn.effective_at::date BETWEEN cycle_start AND cycle_end;

    -- 4. Verify new wallet balance (after returning old amount if it's the same wallet)
    SELECT balance INTO v_new_wallet_balance FROM public.wallets WHERE id = p_new_from_wallet_id;
    IF v_new_wallet_balance < p_new_amount THEN
        RAISE EXCEPTION 'INSUFFICIENT_BALANCE';
    END IF;

    -- 5. Create new modified transaction (MUST BE EXPENSE TYPE)
    INSERT INTO public.ledger_transactions (
        family_id, type, amount, from_wallet_id, to_wallet_id,
        category_id, status, created_by, effective_at, description, notes, metadata
    ) VALUES (
        p_family_id, 'EXPENSE', p_new_amount, p_new_from_wallet_id, NULL,
        p_new_category_id, 'POSTED', v_member.id, v_eff_at,
        COALESCE(p_new_description, v_orig_txn.description),
        p_new_notes,
        jsonb_build_object('is_correction', true, 'corrected_from', p_original_txn_id)
    ) RETURNING id INTO v_adj_id;

    -- Link as ADJUSTMENT
    INSERT INTO public.transaction_links (family_id, source_transaction_id, related_transaction_id, link_type)
    VALUES (p_family_id, p_original_txn_id, v_adj_id, 'ADJUSTMENT');

    -- Deduct from new wallet
    UPDATE public.wallets
    SET balance = balance - p_new_amount, updated_at = now()
    WHERE id = p_new_from_wallet_id;

    -- Add to new budget
    UPDATE public.budgets
    SET spent_amount = spent_amount + p_new_amount, updated_at = now()
    WHERE family_id = p_family_id
      AND category_id = p_new_category_id
      AND v_eff_at::date BETWEEN cycle_start AND cycle_end;

    -- 6. Attachments Handling
    SELECT * INTO v_orig_att FROM public.transaction_attachments
    WHERE transaction_id = p_original_txn_id AND status = 'ACTIVE' LIMIT 1;

    IF FOUND THEN
        IF p_receipt_mode = 'COPY_TO_ADJUSTMENT' THEN
            INSERT INTO public.transaction_attachments (
                family_id, transaction_id, attachment_type, storage_path, file_name, mime_type, file_size_bytes, uploaded_by, metadata
            ) VALUES (
                p_family_id, v_adj_id, v_orig_att.attachment_type, v_orig_att.storage_path, v_orig_att.file_name, v_orig_att.mime_type, v_orig_att.file_size_bytes, v_orig_att.uploaded_by, v_orig_att.metadata
            ) RETURNING id INTO v_new_att_id;
        ELSIF p_receipt_mode = 'MOVE_TO_ADJUSTMENT' THEN
            UPDATE public.transaction_attachments SET status = 'REPLACED', updated_at = now() WHERE id = v_orig_att.id;
            INSERT INTO public.transaction_attachments (
                family_id, transaction_id, attachment_type, storage_path, file_name, mime_type, file_size_bytes, uploaded_by, metadata
            ) VALUES (
                p_family_id, v_adj_id, v_orig_att.attachment_type, v_orig_att.storage_path, v_orig_att.file_name, v_orig_att.mime_type, v_orig_att.file_size_bytes, v_orig_att.uploaded_by, v_orig_att.metadata
            ) RETURNING id INTO v_new_att_id;
        END IF;
    END IF;

    -- 7. Audit Logging
    INSERT INTO public.audit_events (family_id, actor_id, action, target_id, target_type, details)
    VALUES (
        p_family_id, v_member.id, 'EXPENSE_CORRECTED', p_original_txn_id, 'ledger_transactions',
        jsonb_build_object(
            'old_amount', v_orig_txn.amount,
            'old_wallet_id', v_orig_txn.from_wallet_id,
            'old_category_id', v_orig_txn.category_id,
            'new_amount', p_new_amount,
            'new_wallet_id', p_new_from_wallet_id,
            'new_category_id', p_new_category_id,
            'reversal_id', v_reversal_id,
            'adjustment_id', v_adj_id,
            'receipt_mode', p_receipt_mode
        )
    );

    RETURN QUERY SELECT v_reversal_id, v_adj_id;
END;
$$;
