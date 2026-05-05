-- Mezan: 00044_expense_correction_wallet_parity.test.sql

BEGIN;

-- 1. Setup Test Data
DECLARE
    v_user_1 uuid := gen_random_uuid();
    v_family_1 uuid;
    v_cat_exp uuid;
    v_wallet_real uuid;
    v_wallet_alloc uuid;
    v_wallet_other_family uuid;
    v_family_2 uuid;
    v_budget_1 uuid;
    v_expense_id uuid;
    v_rev_id uuid;
    v_adj_id uuid;
BEGIN
    -- Create User 1
    INSERT INTO auth.users (id, email) VALUES (v_user_1, 'test44@mezan.com');
    
    -- Create Family 1 & 2
    v_family_1 := public.fn_create_initial_family(v_user_1, 'Test Family 44');
    
    INSERT INTO public.family_groups (id, name, created_by) VALUES (gen_random_uuid(), 'Other Family 44', v_user_1) RETURNING id INTO v_family_2;
    INSERT INTO public.family_members (family_id, user_id, role, status) VALUES (v_family_2, v_user_1, 'OWNER', 'ACTIVE');

    -- Create Categories
    INSERT INTO public.categories (family_id, name, direction, is_system) 
    VALUES (v_family_1, 'Test Expense Cat 44', 'EXPENSE', false) RETURNING id INTO v_cat_exp;

    -- Create Wallets
    INSERT INTO public.wallets (family_id, name, type, balance, created_by)
    VALUES (v_family_1, 'Real Wallet', 'REAL', 5000, v_user_1) RETURNING id INTO v_wallet_real;

    INSERT INTO public.wallets (family_id, name, type, balance, created_by)
    VALUES (v_family_1, 'Allocated Wallet', 'ALLOCATED', 2000, v_user_1) RETURNING id INTO v_wallet_alloc;

    INSERT INTO public.wallets (family_id, name, type, balance, created_by)
    VALUES (v_family_2, 'Other Family Real Wallet', 'REAL', 10000, v_user_1) RETURNING id INTO v_wallet_other_family;

    -- Create Budget
    v_budget_1 := public.fn_create_budget(
        p_family_id := v_family_1,
        p_category_id := v_cat_exp,
        p_cycle_start := date_trunc('month', now())::date,
        p_cycle_end := (date_trunc('month', now()) + interval '1 month - 1 day')::date,
        p_allocated_amount := 10000,
        p_period := 'MONTHLY'
    );

    -- Simulate Auth
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE 'SET LOCAL request.jwt.claims = ''{"sub": "' || v_user_1 || '"}''';

    -- Test 1: Expense from ALLOCATED wallet can be corrected to the same ALLOCATED wallet
    v_expense_id := public.fn_record_expense(
        p_family_id := v_family_1,
        p_amount := 500,
        p_from_wallet_id := v_wallet_alloc,
        p_category_id := v_cat_exp,
        p_description := 'Allocated Expense 1'
    );

    SELECT reversal_id, adjustment_id INTO v_rev_id, v_adj_id 
    FROM public.fn_correct_expense_transaction(
        p_family_id := v_family_1,
        p_original_txn_id := v_expense_id,
        p_new_amount := 600,
        p_new_from_wallet_id := v_wallet_alloc,
        p_new_category_id := v_cat_exp
    );

    IF v_rev_id IS NULL OR v_adj_id IS NULL THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Could not correct allocated expense';
    END IF;

    -- Test 2: Expense from REAL wallet can be corrected to ALLOCATED wallet
    v_expense_id := public.fn_record_expense(
        p_family_id := v_family_1,
        p_amount := 100,
        p_from_wallet_id := v_wallet_real,
        p_category_id := v_cat_exp,
        p_description := 'Real Expense'
    );

    SELECT reversal_id, adjustment_id INTO v_rev_id, v_adj_id 
    FROM public.fn_correct_expense_transaction(
        p_family_id := v_family_1,
        p_original_txn_id := v_expense_id,
        p_new_amount := 200,
        p_new_from_wallet_id := v_wallet_alloc,
        p_new_category_id := v_cat_exp
    );

    IF v_rev_id IS NULL OR v_adj_id IS NULL THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Could not correct from REAL to ALLOCATED';
    END IF;

    -- Test 3: Cannot correct to a wallet from another family
    BEGIN
        PERFORM public.fn_correct_expense_transaction(
            p_family_id := v_family_1,
            p_original_txn_id := v_adj_id, -- the last adjustment
            p_new_amount := 100,
            p_new_from_wallet_id := v_wallet_other_family,
            p_new_category_id := v_cat_exp
        );
        RAISE EXCEPTION 'TEST 3 FAILED: Allowed correction to another family wallet';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'TEST 3 FAILED: Allowed correction to another family wallet' THEN RAISE; END IF;
        -- Expected
    END;

    RAISE NOTICE 'ALL TESTS PASSED SUCCESSFULLY';
END;
$$;

ROLLBACK;
