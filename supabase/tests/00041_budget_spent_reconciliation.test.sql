-- =============================================================================
-- Mezan: 00041_budget_spent_reconciliation.test.sql
-- =============================================================================

BEGIN;

-- 1. Create a mock category, wallet, and family
DO $$
DECLARE
  v_family_id UUID;
  v_owner_id UUID;
  v_wallet_id UUID;
  v_category_id UUID;
  v_budget_id UUID;
  v_txn_id UUID;
  v_spent NUMERIC(14,2);
  v_test_start DATE := '2026-05-01';
  v_test_end DATE := '2026-05-31';
BEGIN
  -- We assume standard test data is already set up by previous tests if needed,
  -- but we can use the main test family or create one. We'll use the fn_register_user for a fresh test.
  
  -- Create isolated user/family
  SELECT user_id, family_id INTO v_owner_id, v_family_id 
  FROM public.fn_register_user('budget_recon@test.local', 'Test Owner');

  -- Create wallet
  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (v_family_id, 'Test Wallet', 'REAL', 5000, v_owner_id)
  RETURNING id INTO v_wallet_id;

  -- Create category
  INSERT INTO public.categories (family_id, name_ar, name_en, type, direction, icon)
  VALUES (v_family_id, 'Test Category', 'Test', 'CUSTOM', 'EXPENSE', 'test')
  RETURNING id INTO v_category_id;

  -- Create an initial expense BEFORE budget exists
  v_txn_id := public.fn_record_expense(
    v_family_id, 
    200.00, 
    v_wallet_id, 
    v_category_id, 
    'Expense 1', 
    '2026-05-15 10:00:00+00'::timestamptz
  );

  -- Create a budget
  v_budget_id := public.fn_create_budget(
    v_family_id,
    v_category_id,
    v_test_start,
    v_test_end,
    1000.00,
    'MONTHLY'
  );

  -- 1. Check if fn_create_budget backfilled correctly
  SELECT spent_amount INTO v_spent FROM public.budgets WHERE id = v_budget_id;
  IF v_spent != 200.00 THEN
    RAISE EXCEPTION 'TEST_FAILED: Initial backfill was incorrect. Expected 200, got %', v_spent;
  END IF;

  -- Create another expense inside budget period
  PERFORM public.fn_record_expense(
    v_family_id, 
    150.00, 
    v_wallet_id, 
    v_category_id, 
    'Expense 2', 
    '2026-05-20 10:00:00+00'::timestamptz
  );

  SELECT spent_amount INTO v_spent FROM public.budgets WHERE id = v_budget_id;
  IF v_spent != 350.00 THEN
    RAISE EXCEPTION 'TEST_FAILED: Expense recording did not update budget correctly. Expected 350, got %', v_spent;
  END IF;

  -- Now intentionally corrupt the budget spent amount
  UPDATE public.budgets SET spent_amount = 0 WHERE id = v_budget_id;

  -- Call the reconciliation RPC
  PERFORM public.fn_recalculate_budget_spent(v_budget_id);

  -- Verify it was restored
  SELECT spent_amount INTO v_spent FROM public.budgets WHERE id = v_budget_id;
  IF v_spent != 350.00 THEN
    RAISE EXCEPTION 'TEST_FAILED: Reconciliation failed. Expected 350, got %', v_spent;
  END IF;

  -- Add an out-of-period expense, should not affect budget
  PERFORM public.fn_record_expense(
    v_family_id, 
    500.00, 
    v_wallet_id, 
    v_category_id, 
    'Out of period', 
    '2026-06-05 10:00:00+00'::timestamptz
  );

  PERFORM public.fn_recalculate_budget_spent(v_budget_id);
  SELECT spent_amount INTO v_spent FROM public.budgets WHERE id = v_budget_id;
  IF v_spent != 350.00 THEN
    RAISE EXCEPTION 'TEST_FAILED: Out of period expense affected budget. Expected 350, got %', v_spent;
  END IF;

  -- Reverse one transaction to ensure it is excluded
  PERFORM public.fn_correct_transaction(v_family_id, v_txn_id);

  PERFORM public.fn_recalculate_budget_spent(v_budget_id);
  SELECT spent_amount INTO v_spent FROM public.budgets WHERE id = v_budget_id;
  IF v_spent != 150.00 THEN
    RAISE EXCEPTION 'TEST_FAILED: Reversed transaction still included. Expected 150, got %', v_spent;
  END IF;

  RAISE NOTICE 'BUDGET RECONCILIATION TESTS PASSED!';
END $$;

ROLLBACK;
