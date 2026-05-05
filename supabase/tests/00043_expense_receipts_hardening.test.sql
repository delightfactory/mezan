-- supabase/tests/00043_expense_receipts_hardening.test.sql
BEGIN;

-- Utility func to run tests
CREATE OR REPLACE FUNCTION assert_true(condition boolean, msg text) RETURNS void AS $$
BEGIN
    IF NOT condition THEN
        RAISE EXCEPTION 'Test Failed: %', msg;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION assert_eq(a numeric, b numeric, msg text) RETURNS void AS $$
BEGIN
    IF a IS DISTINCT FROM b THEN
        RAISE EXCEPTION 'Test Failed: % (Expected %, got %)', msg, a, b;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION assert_eq_text(a text, b text, msg text) RETURNS void AS $$
BEGIN
    IF a IS DISTINCT FROM b THEN
        RAISE EXCEPTION 'Test Failed: % (Expected %, got %)', msg, a, b;
    END IF;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    v_family_1 uuid;
    v_member_1 uuid;
    v_family_2 uuid;
    v_member_2 uuid;
    
    v_wallet_1 uuid;
    v_wallet_2 uuid;
    
    v_cat_exp_1 uuid;
    v_cat_exp_2 uuid;
    
    v_budget_1 uuid;
    v_budget_2 uuid;
    
    v_txn_1 uuid;
    v_txn_2_reversal uuid;
    v_txn_2_adj uuid;
    v_txn_other uuid;
    
    v_att_1 uuid;
    v_att_2 uuid;
    v_att_3 uuid;
    
    v_error_msg text;
    v_reversal_id uuid;
    v_adj_id uuid;
BEGIN
    -- Mock Auth
    v_member_1 := gen_random_uuid();
    v_member_2 := gen_random_uuid();
    
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_member_1::text)::text, true);

    -- Setup
    SELECT family_id, member_id INTO v_family_1, v_member_1 FROM public.fn_create_initial_family('Test Family 1', 'Owner 1');
    
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_member_2::text)::text, true);
    SELECT family_id, member_id INTO v_family_2, v_member_2 FROM public.fn_create_initial_family('Test Family 2', 'Owner 2');

    -- Switch back to user 1 for the rest
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_member_1::text)::text, true);

    -- Create Wallets
    INSERT INTO public.wallets (family_id, name, type, balance, created_by)
    VALUES (v_family_1, 'Main Wallet', 'REAL', 10000, v_member_1) RETURNING id INTO v_wallet_1;
    
    INSERT INTO public.wallets (family_id, name, type, balance, created_by)
    VALUES (v_family_1, 'Savings', 'REAL', 5000, v_member_1) RETURNING id INTO v_wallet_2;

    -- Create Categories using named parameters
    v_cat_exp_1 := public.fn_create_family_category(
        p_family_id := v_family_1,
        p_name_ar := 'Food',
        p_name_en := NULL,
        p_icon := NULL,
        p_direction := 'EXPENSE'
    );
    v_cat_exp_2 := public.fn_create_family_category(
        p_family_id := v_family_1,
        p_name_ar := 'Transport',
        p_name_en := NULL,
        p_icon := NULL,
        p_direction := 'EXPENSE'
    );

    -- Create Budgets for current month
    v_budget_1 := public.fn_create_budget(
        p_family_id := v_family_1,
        p_category_id := v_cat_exp_1,
        p_cycle_start := date_trunc('month', now())::date,
        p_cycle_end := (date_trunc('month', now()) + interval '1 month - 1 day')::date,
        p_allocated_amount := 2000,
        p_period := 'MONTHLY'
    );
    v_budget_2 := public.fn_create_budget(
        p_family_id := v_family_1,
        p_category_id := v_cat_exp_2,
        p_cycle_start := date_trunc('month', now())::date,
        p_cycle_end := (date_trunc('month', now()) + interval '1 month - 1 day')::date,
        p_allocated_amount := 1000,
        p_period := 'MONTHLY'
    );

    -- Record initial expense
    v_txn_1 := public.fn_record_expense(
        p_family_id := v_family_1,
        p_amount := 500,
        p_from_wallet_id := v_wallet_1,
        p_category_id := v_cat_exp_1,
        p_description := 'Groceries'
    );
    
    -- Verify initial balance and budget
    PERFORM assert_eq((SELECT balance FROM public.wallets WHERE id = v_wallet_1), 9500, 'Wallet balance after txn1');
    PERFORM assert_eq((SELECT spent_amount FROM public.budgets WHERE id = v_budget_1), 500, 'Budget spent after txn1');

    ---------------------------------------------------------------------------
    -- TEST 1: Attach receipt successfully with validated path
    ---------------------------------------------------------------------------
    v_att_1 := public.fn_attach_transaction_receipt(
        p_family_id := v_family_1,
        p_transaction_id := v_txn_1,
        p_storage_path := v_family_1::text || '/' || v_txn_1::text || '/receipt_1.jpg',
        p_file_name := 'r1.jpg',
        p_mime_type := 'image/jpeg',
        p_file_size_bytes := 1024,
        p_attachment_type := 'RECEIPT'
    );
    PERFORM assert_true(v_att_1 IS NOT NULL, 'Receipt attached successfully');

    ---------------------------------------------------------------------------
    -- TEST 2: Cannot attach receipt with invalid path
    ---------------------------------------------------------------------------
    BEGIN
        PERFORM public.fn_attach_transaction_receipt(
            p_family_id := v_family_1,
            p_transaction_id := v_txn_1,
            p_storage_path := 'some/random/path.jpg',
            p_file_name := 'file.jpg',
            p_mime_type := 'image/jpeg',
            p_file_size_bytes := 1024,
            p_attachment_type := 'RECEIPT'
        );
        RAISE EXCEPTION 'Should have failed due to invalid path';
    EXCEPTION WHEN OTHERS THEN
        v_error_msg := SQLERRM;
        PERFORM assert_true(v_error_msg ILIKE '%INVALID_STORAGE_PATH%', 'Invalid path check');
    END;

    ---------------------------------------------------------------------------
    -- TEST 3: Replace receipt with valid path
    ---------------------------------------------------------------------------
    v_att_2 := public.fn_replace_transaction_receipt(
        p_family_id := v_family_1,
        p_old_attachment_id := v_att_1,
        p_new_storage_path := v_family_1::text || '/' || v_txn_1::text || '/receipt_new.pdf',
        p_new_file_name := 'new.pdf',
        p_new_mime_type := 'application/pdf',
        p_new_file_size_bytes := 2048
    );
    PERFORM assert_true(v_att_2 IS NOT NULL, 'Receipt replaced');
    PERFORM assert_eq_text((SELECT status FROM public.transaction_attachments WHERE id = v_att_1), 'REPLACED', 'Old receipt replaced');

    ---------------------------------------------------------------------------
    -- TEST 4: Correct expense (Change amount and category) with COPY_TO_ADJUSTMENT
    ---------------------------------------------------------------------------
    -- Change from 500 (Food) to 800 (Transport)
    SELECT reversal_id, adjustment_id INTO v_reversal_id, v_adj_id 
    FROM public.fn_correct_expense_transaction(
        p_family_id := v_family_1,
        p_original_txn_id := v_txn_1,
        p_new_amount := 800,
        p_new_from_wallet_id := v_wallet_1,
        p_new_category_id := v_cat_exp_2,
        p_new_description := 'New Groceries',
        p_receipt_mode := 'COPY_TO_ADJUSTMENT'
    );

    -- Checks:
    PERFORM assert_eq_text((SELECT status FROM public.ledger_transactions WHERE id = v_txn_1), 'REVERSED', 'Orig txn reversed');
    PERFORM assert_eq_text((SELECT status FROM public.ledger_transactions WHERE id = v_adj_id), 'POSTED', 'Adj txn posted');
    -- Wallet Balance: Initial 10000 -> -500 + 500 - 800 = 9200
    PERFORM assert_eq((SELECT balance FROM public.wallets WHERE id = v_wallet_1), 9200, 'Wallet balance corrected');
    -- Budgets: Food (0), Transport (800)
    PERFORM assert_eq((SELECT spent_amount FROM public.budgets WHERE id = v_budget_1), 0, 'Food budget reset');
    PERFORM assert_eq((SELECT spent_amount FROM public.budgets WHERE id = v_budget_2), 800, 'Transport budget updated');
    -- Attachment copied
    PERFORM assert_true(EXISTS(
        SELECT 1 FROM public.transaction_attachments 
        WHERE transaction_id = v_adj_id AND status = 'ACTIVE' AND storage_path = v_family_1::text || '/' || v_txn_1::text || '/receipt_new.pdf'
    ), 'Attachment copied to adjustment');

    ---------------------------------------------------------------------------
    -- TEST 5: Correct expense with Wallet from Another Family (Should Fail)
    ---------------------------------------------------------------------------
    -- We'll create a wallet in family 2 and try to use it in fn_correct_expense_transaction for family 1
    DECLARE
        v_wallet_f2 uuid;
    BEGIN
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_member_2::text)::text, true);
        INSERT INTO public.wallets (family_id, name, type, balance, created_by)
        VALUES (v_family_2, 'Family 2 Wallet', 'REAL', 10000, v_member_2) RETURNING id INTO v_wallet_f2;
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_member_1::text)::text, true);
        
        BEGIN
            PERFORM public.fn_correct_expense_transaction(
                p_family_id := v_family_1,
                p_original_txn_id := v_adj_id,
                p_new_amount := 900,
                p_new_from_wallet_id := v_wallet_f2,
                p_new_category_id := v_cat_exp_2,
                p_receipt_mode := 'KEEP_ON_ORIGINAL'
            );
            RAISE EXCEPTION 'Should have failed cross family wallet';
        EXCEPTION WHEN OTHERS THEN
            v_error_msg := SQLERRM;
            PERFORM assert_true(v_error_msg ILIKE '%WALLET_NOT_FOUND%', 'Cross family wallet check works');
        END;
    END;

    ---------------------------------------------------------------------------
    -- TEST 6: Correct expense (Insufficient balance)
    ---------------------------------------------------------------------------
    -- Current balance of wallet_2 is 5000. Let's try to change it to 6000.
    BEGIN
        PERFORM public.fn_correct_expense_transaction(
            p_family_id := v_family_1,
            p_original_txn_id := v_adj_id,
            p_new_amount := 6000,
            p_new_from_wallet_id := v_wallet_2,
            p_new_category_id := v_cat_exp_2,
            p_receipt_mode := 'KEEP_ON_ORIGINAL'
        );
        RAISE EXCEPTION 'Should have failed insufficient balance';
    EXCEPTION WHEN OTHERS THEN
        v_error_msg := SQLERRM;
        PERFORM assert_true(v_error_msg ILIKE '%INSUFFICIENT_BALANCE%', 'Insufficient balance check works');
    END;

    ---------------------------------------------------------------------------
    -- TEST 7: Delete receipt
    ---------------------------------------------------------------------------
    -- Find the new copied attachment
    SELECT id INTO v_att_3 FROM public.transaction_attachments WHERE transaction_id = v_adj_id AND status = 'ACTIVE';
    PERFORM public.fn_delete_transaction_receipt(
        p_family_id := v_family_1,
        p_attachment_id := v_att_3
    );
    PERFORM assert_eq_text((SELECT status FROM public.transaction_attachments WHERE id = v_att_3), 'DELETED', 'Receipt deleted');

    RAISE NOTICE 'All tests passed!';
END $$;

ROLLBACK;
