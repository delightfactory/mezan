-- 00043_expense_receipts_hardening.sql

-- 1. Drop storage path uniqueness to allow COPY_TO_ADJUSTMENT/MOVE_TO_ADJUSTMENT
ALTER TABLE public.transaction_attachments DROP CONSTRAINT IF EXISTS uq_storage_path;

-- 2. Recreate fn_attach_transaction_receipt with search_path, path validation and explicit grants
CREATE OR REPLACE FUNCTION public.fn_attach_transaction_receipt(
    p_family_id uuid,
    p_transaction_id uuid,
    p_storage_path text,
    p_file_name text,
    p_mime_type text,
    p_file_size_bytes bigint,
    p_attachment_type text DEFAULT 'RECEIPT',
    p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_member public.family_members;
    v_txn public.ledger_transactions;
    v_attachment_id uuid;
BEGIN
    -- Verify member
    SELECT * INTO v_member FROM public._require_member(p_family_id, ARRAY['OWNER', 'MEMBER']::public.member_role[]);

    -- Verify transaction
    SELECT * INTO v_txn FROM public.ledger_transactions
    WHERE id = p_transaction_id AND family_id = p_family_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transaction not found';
    END IF;

    IF v_txn.type != 'EXPENSE' THEN
        RAISE EXCEPTION 'Cannot attach receipt to non-expense transaction';
    END IF;

    IF v_txn.status != 'POSTED' THEN
        RAISE EXCEPTION 'Cannot attach receipt to non-posted transaction';
    END IF;
    
    -- Validate storage_path explicitly
    IF p_storage_path NOT LIKE p_family_id::text || '/' || p_transaction_id::text || '/%' THEN
        RAISE EXCEPTION 'INVALID_STORAGE_PATH';
    END IF;

    -- Verify MIME type
    IF p_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf') THEN
        RAISE EXCEPTION 'Invalid mime type';
    END IF;

    -- Maximum file size 10MB
    IF p_file_size_bytes > 10485760 THEN
        RAISE EXCEPTION 'File size exceeds 10MB limit';
    END IF;

    INSERT INTO public.transaction_attachments (
        family_id,
        transaction_id,
        attachment_type,
        storage_path,
        file_name,
        mime_type,
        file_size_bytes,
        uploaded_by,
        metadata
    ) VALUES (
        p_family_id,
        p_transaction_id,
        p_attachment_type,
        p_storage_path,
        p_file_name,
        p_mime_type,
        p_file_size_bytes,
        v_member.id,
        p_metadata
    ) RETURNING id INTO v_attachment_id;

    -- Log audit
    INSERT INTO public.audit_events (family_id, actor_id, action, target_id, target_type, details)
    VALUES (
        p_family_id, v_member.id, 'RECEIPT_ATTACHED', p_transaction_id, 'ledger_transactions',
        jsonb_build_object(
            'attachment_id', v_attachment_id,
            'file_name', p_file_name
        )
    );

    RETURN v_attachment_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_attach_transaction_receipt(uuid, uuid, text, text, text, bigint, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_attach_transaction_receipt(uuid, uuid, text, text, text, bigint, text, jsonb) TO authenticated;


-- 3. Recreate fn_delete_transaction_receipt
CREATE OR REPLACE FUNCTION public.fn_delete_transaction_receipt(
    p_family_id uuid,
    p_attachment_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_member public.family_members;
    v_att public.transaction_attachments;
BEGIN
    SELECT * INTO v_member FROM public._require_member(p_family_id, ARRAY['OWNER', 'MEMBER']::public.member_role[]);

    SELECT * INTO v_att FROM public.transaction_attachments
    WHERE id = p_attachment_id AND family_id = p_family_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Attachment not found';
    END IF;

    IF v_att.status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Attachment is already %', v_att.status;
    END IF;

    UPDATE public.transaction_attachments
    SET status = 'DELETED',
        deleted_at = now(),
        updated_at = now()
    WHERE id = p_attachment_id;

    -- Log audit
    INSERT INTO public.audit_events (family_id, actor_id, action, target_id, target_type, details)
    VALUES (
        p_family_id, v_member.id, 'RECEIPT_DELETED', v_att.transaction_id, 'ledger_transactions',
        jsonb_build_object('attachment_id', p_attachment_id)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_delete_transaction_receipt(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_delete_transaction_receipt(uuid, uuid) TO authenticated;


-- 4. Recreate fn_replace_transaction_receipt
CREATE OR REPLACE FUNCTION public.fn_replace_transaction_receipt(
    p_family_id uuid,
    p_old_attachment_id uuid,
    p_new_storage_path text,
    p_new_file_name text,
    p_new_mime_type text,
    p_new_file_size_bytes bigint,
    p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_member public.family_members;
    v_old_att public.transaction_attachments;
    v_new_id uuid;
BEGIN
    SELECT * INTO v_member FROM public._require_member(p_family_id, ARRAY['OWNER', 'MEMBER']::public.member_role[]);

    SELECT * INTO v_old_att FROM public.transaction_attachments
    WHERE id = p_old_attachment_id AND family_id = p_family_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Old attachment not found';
    END IF;

    IF v_old_att.status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Old attachment is not active';
    END IF;
    
    -- Validate storage_path explicitly against old transaction_id
    IF p_new_storage_path NOT LIKE p_family_id::text || '/' || v_old_att.transaction_id::text || '/%' THEN
        RAISE EXCEPTION 'INVALID_STORAGE_PATH';
    END IF;

    -- Verify MIME type
    IF p_new_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf') THEN
        RAISE EXCEPTION 'Invalid mime type';
    END IF;

    IF p_new_file_size_bytes > 10485760 THEN
        RAISE EXCEPTION 'File size exceeds 10MB limit';
    END IF;

    -- Mark old as replaced
    UPDATE public.transaction_attachments
    SET status = 'REPLACED',
        updated_at = now()
    WHERE id = p_old_attachment_id;

    -- Create new
    INSERT INTO public.transaction_attachments (
        family_id,
        transaction_id,
        attachment_type,
        storage_path,
        file_name,
        mime_type,
        file_size_bytes,
        uploaded_by,
        metadata
    ) VALUES (
        p_family_id,
        v_old_att.transaction_id,
        v_old_att.attachment_type,
        p_new_storage_path,
        p_new_file_name,
        p_new_mime_type,
        p_new_file_size_bytes,
        v_member.id,
        p_metadata
    ) RETURNING id INTO v_new_id;

    -- Log audit
    INSERT INTO public.audit_events (family_id, actor_id, action, target_id, target_type, details)
    VALUES (
        p_family_id, v_member.id, 'RECEIPT_REPLACED', v_old_att.transaction_id, 'ledger_transactions',
        jsonb_build_object(
            'old_attachment_id', p_old_attachment_id,
            'new_attachment_id', v_new_id
        )
    );

    RETURN v_new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_replace_transaction_receipt(uuid, uuid, text, text, text, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_replace_transaction_receipt(uuid, uuid, text, text, text, bigint, jsonb) TO authenticated;


-- 5. Recreate fn_correct_expense_transaction
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

    SELECT * INTO v_w1 FROM public.wallets WHERE id = v_first_wallet AND family_id = p_family_id AND is_archived = false AND type = 'REAL' FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'WALLET_NOT_FOUND';
    END IF;

    IF v_first_wallet != v_second_wallet THEN
        SELECT * INTO v_w2 FROM public.wallets WHERE id = v_second_wallet AND family_id = p_family_id AND is_archived = false AND type = 'REAL' FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'WALLET_NOT_FOUND';
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

REVOKE ALL ON FUNCTION public.fn_correct_expense_transaction(uuid, uuid, numeric, uuid, uuid, text, timestamptz, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_correct_expense_transaction(uuid, uuid, numeric, uuid, uuid, text, timestamptz, text, text) TO authenticated;
