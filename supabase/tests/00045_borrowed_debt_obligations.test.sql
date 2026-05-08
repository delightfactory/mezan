-- =============================================================================
-- Mezan: 00045_borrowed_debt_obligations.test.sql
-- Integration tests for Borrowed Debt Obligations system
--
-- Pattern: DO block with ROLLBACK-via-exception (matches project standard).
-- All schema references validated against migration 00045 and 00005.
--
-- Covers:
--   T01 - MONTHLY_INSTALLMENT debt creates correct occurrences
--   T02 - ONE_TIME debt creates exactly one occurrence
--   T03 - FLEXIBLE debt creates NO occurrences
--   T04 - Partial payment: paid_amount increases, PARTIALLY_PAID status, installments_paid unchanged
--   T05 - Full occurrence payment: status=PAID, installments_paid incremented once
--   T06 - Overpayment on occurrence is rejected (OCCURRENCE_OVERPAYMENT_NOT_ALLOWED)
--   T07 - Safe-to-spend: no double-counting for debts with occurrences
--   T08 - Safe-to-spend: PARTIALLY_PAID occurrence deducts only remaining amount
--   T09 - Safe-to-spend: legacy FLEXIBLE debt (no occurrences) uses fallback correctly
--   T10 - Settling a debt cancels remaining occurrences
--   T11 - Payroll deduction with occurrence: partial payment works
--   T12 - fn_reschedule_debt regenerates occurrences from remaining amount
-- =============================================================================

DO $$
DECLARE
  v_user_id   UUID := gen_random_uuid();
  v_family_id UUID;
  v_member_id UUID;
  v_wallet_id UUID;
  v_cat_id    UUID;
  v_debt_id   UUID;
  v_occ_1_id  UUID;
  v_occ_2_id  UUID;
  v_safe      NUMERIC;
  v_safe_after NUMERIC;
  v_count     INT;
  v_paid_amt  NUMERIC;
  v_status    TEXT;
  v_inst_paid INT;
  v_remaining NUMERIC;
  v_cycle_end DATE;
BEGIN
  -- ── Setup ─────────────────────────────────────────────────────────────────
  -- auth.users: full pattern matching project standard
  INSERT INTO auth.users (id, email, aud, role, encrypted_password, created_at, updated_at)
  VALUES (
    v_user_id,
    'test45_' || v_user_id || '@mezan.test',
    'authenticated',
    'authenticated',
    'test-password-hash',
    now(),
    now()
  );

  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);
  PERFORM set_config('role', 'authenticated', true);

  SELECT family_id, member_id INTO v_family_id, v_member_id
  FROM public.fn_create_initial_family('Test Debt Obligations Family 45', 'Test Owner 45');

  -- REAL wallet with opening balance 50,000
  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (v_family_id, 'Main Real Wallet', 'REAL', 50000, v_member_id)
  RETURNING id INTO v_wallet_id;

  -- Income category for payroll test (name_ar + behavior required by schema)
  INSERT INTO public.categories (family_id, name_ar, name_en, direction, is_system, behavior)
  VALUES (v_family_id, 'مرتب', 'Salary', 'INCOME', false, 'FIXED_ESSENTIAL')
  RETURNING id INTO v_cat_id;

  v_cycle_end := (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date;

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T01: MONTHLY_INSTALLMENT creates correct occurrences
  -- Loan: 3000 | installment: 1000 | count: 3
  -- Expected: 3 occurrences of 1000 each, status UPCOMING
  -- ═══════════════════════════════════════════════════════════════════════════
  SELECT debt_id INTO v_debt_id FROM public.fn_receive_loan(
    p_family_id             => v_family_id,
    p_entity_name           => 'T01 Bank Loan',
    p_amount                => 3000,
    p_wallet_id             => v_wallet_id,
    p_payment_schedule_type => 'MONTHLY_INSTALLMENT',
    p_next_due_date         => v_cycle_end + 1,
    p_monthly_installment   => 1000,
    p_installment_count     => 3
  );

  SELECT COUNT(*) INTO v_count
  FROM public.debt_due_occurrences WHERE debt_id = v_debt_id;

  IF v_count != 3 THEN
    RAISE EXCEPTION 'T01 FAILED: Expected 3 occurrences, got %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.debt_due_occurrences
  WHERE debt_id = v_debt_id AND amount = 1000 AND status = 'UPCOMING';

  IF v_count != 3 THEN
    RAISE EXCEPTION 'T01 FAILED: Expected 3 x 1000 UPCOMING occurrences, got %', v_count;
  END IF;

  RAISE NOTICE 'T01 PASSED: MONTHLY_INSTALLMENT creates correct occurrences';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T02: ONE_TIME debt creates exactly one occurrence
  -- ═══════════════════════════════════════════════════════════════════════════
  SELECT debt_id INTO v_debt_id FROM public.fn_receive_loan(
    p_family_id             => v_family_id,
    p_entity_name           => 'T02 Friend Loan',
    p_amount                => 2000,
    p_wallet_id             => v_wallet_id,
    p_payment_schedule_type => 'ONE_TIME',
    p_next_due_date         => v_cycle_end + 30
  );

  SELECT COUNT(*) INTO v_count
  FROM public.debt_due_occurrences WHERE debt_id = v_debt_id;

  IF v_count != 1 THEN
    RAISE EXCEPTION 'T02 FAILED: ONE_TIME expected 1 occurrence, got %', v_count;
  END IF;

  -- Check occurrence amount equals full debt amount
  SELECT amount INTO v_paid_amt
  FROM public.debt_due_occurrences WHERE debt_id = v_debt_id LIMIT 1;

  IF v_paid_amt != 2000 THEN
    RAISE EXCEPTION 'T02 FAILED: ONE_TIME occurrence amount wrong, got %', v_paid_amt;
  END IF;

  RAISE NOTICE 'T02 PASSED: ONE_TIME creates exactly one occurrence';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T03: FLEXIBLE debt creates NO occurrences
  -- ═══════════════════════════════════════════════════════════════════════════
  SELECT debt_id INTO v_debt_id FROM public.fn_receive_loan(
    p_family_id             => v_family_id,
    p_entity_name           => 'T03 Flexible Cousin',
    p_amount                => 1500,
    p_wallet_id             => v_wallet_id,
    p_payment_schedule_type => 'FLEXIBLE'
  );

  SELECT COUNT(*) INTO v_count
  FROM public.debt_due_occurrences WHERE debt_id = v_debt_id;

  IF v_count != 0 THEN
    RAISE EXCEPTION 'T03 FAILED: FLEXIBLE expected 0 occurrences, got %', v_count;
  END IF;

  RAISE NOTICE 'T03 PASSED: FLEXIBLE creates no occurrences';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T04: Partial payment — paid_amount increases, PARTIALLY_PAID, installments_paid unchanged
  -- Debt: 2000 | 2 installments of 1000 each | due today
  -- ═══════════════════════════════════════════════════════════════════════════
  SELECT debt_id INTO v_debt_id FROM public.fn_receive_loan(
    p_family_id             => v_family_id,
    p_entity_name           => 'T04 Partial Payment Loan',
    p_amount                => 2000,
    p_wallet_id             => v_wallet_id,
    p_payment_schedule_type => 'MONTHLY_INSTALLMENT',
    p_next_due_date         => CURRENT_DATE,
    p_monthly_installment   => 1000,
    p_installment_count     => 2
  );

  SELECT id INTO v_occ_1_id
  FROM public.debt_due_occurrences
  WHERE debt_id = v_debt_id
  ORDER BY sequence_no ASC LIMIT 1;

  -- Pay 400 out of 1000 (partial)
  PERFORM public.fn_record_debt_payment(
    p_family_id              => v_family_id,
    p_debt_id                => v_debt_id,
    p_amount                 => 400,
    p_wallet_id              => v_wallet_id,
    p_debt_due_occurrence_id => v_occ_1_id
  );

  SELECT paid_amount, status INTO v_paid_amt, v_status
  FROM public.debt_due_occurrences WHERE id = v_occ_1_id;

  IF v_paid_amt != 400 THEN
    RAISE EXCEPTION 'T04 FAILED: paid_amount expected 400, got %', v_paid_amt;
  END IF;
  IF v_status != 'PARTIALLY_PAID' THEN
    RAISE EXCEPTION 'T04 FAILED: status expected PARTIALLY_PAID, got %', v_status;
  END IF;

  SELECT installments_paid INTO v_inst_paid FROM public.debts WHERE id = v_debt_id;
  IF v_inst_paid != 0 THEN
    RAISE EXCEPTION 'T04 FAILED: installments_paid should be 0 after partial, got %', v_inst_paid;
  END IF;

  RAISE NOTICE 'T04 PASSED: Partial payment sets PARTIALLY_PAID, installments_paid unchanged';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T05: Full occurrence payment — status=PAID, installments_paid incremented ONCE
  -- Continue from T04 — pay remaining 600 on same occurrence
  -- ═══════════════════════════════════════════════════════════════════════════
  PERFORM public.fn_record_debt_payment(
    p_family_id              => v_family_id,
    p_debt_id                => v_debt_id,
    p_amount                 => 600,
    p_wallet_id              => v_wallet_id,
    p_debt_due_occurrence_id => v_occ_1_id
  );

  SELECT paid_amount, status INTO v_paid_amt, v_status
  FROM public.debt_due_occurrences WHERE id = v_occ_1_id;

  IF v_status != 'PAID' THEN
    RAISE EXCEPTION 'T05 FAILED: status expected PAID after full payment, got %', v_status;
  END IF;
  IF v_paid_amt != 1000 THEN
    RAISE EXCEPTION 'T05 FAILED: paid_amount expected 1000, got %', v_paid_amt;
  END IF;

  SELECT installments_paid INTO v_inst_paid FROM public.debts WHERE id = v_debt_id;
  IF v_inst_paid != 1 THEN
    RAISE EXCEPTION 'T05 FAILED: installments_paid expected 1 after full occurrence, got %', v_inst_paid;
  END IF;

  RAISE NOTICE 'T05 PASSED: Full occurrence payment: PAID + installments_paid=1';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T06: Overpayment on occurrence is REJECTED
  -- Try to pay 1500 on an occurrence of 1000
  -- ═══════════════════════════════════════════════════════════════════════════
  SELECT id INTO v_occ_2_id
  FROM public.debt_due_occurrences
  WHERE debt_id = v_debt_id AND status = 'UPCOMING'
  LIMIT 1;

  BEGIN
    PERFORM public.fn_record_debt_payment(
      p_family_id              => v_family_id,
      p_debt_id                => v_debt_id,
      p_amount                 => 1500,
      p_wallet_id              => v_wallet_id,
      p_debt_due_occurrence_id => v_occ_2_id
    );
    RAISE EXCEPTION 'T06 FAILED: Overpayment on occurrence was NOT rejected';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'T06 FAILED: Overpayment on occurrence was NOT rejected' THEN RAISE; END IF;
    IF SQLERRM NOT ILIKE '%OCCURRENCE_OVERPAYMENT_NOT_ALLOWED%' THEN
      RAISE EXCEPTION 'T06 FAILED: Wrong exception: %', SQLERRM;
    END IF;
  END;

  RAISE NOTICE 'T06 PASSED: Overpayment on occurrence rejected correctly';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T07: Safe-to-spend — NO double-counting for debts with occurrences
  -- A MONTHLY_INSTALLMENT debt has occurrences → counted via debt_due_occurrences only.
  -- The legacy debts loop should skip it (NOT EXISTS guard in DB function).
  -- ═══════════════════════════════════════════════════════════════════════════
  v_safe := public.fn_calculate_safe_to_spend(v_family_id);

  SELECT debt_id INTO v_debt_id FROM public.fn_receive_loan(
    p_family_id             => v_family_id,
    p_entity_name           => 'T07 No Double Count',
    p_amount                => 6000,
    p_wallet_id             => v_wallet_id,
    p_payment_schedule_type => 'MONTHLY_INSTALLMENT',
    p_next_due_date         => CURRENT_DATE,        -- due today → within cycle
    p_monthly_installment   => 2000,
    p_installment_count     => 3
  );

  v_safe_after := public.fn_calculate_safe_to_spend(v_family_id);

  -- wallet went up by 6000 (loan received), STS should increase by 6000 - 2000 (first occ) = +4000
  -- If double-counted: STS = v_safe + 6000 - 2000(occ) - 2000(legacy) = v_safe + 2000
  -- If correct:        STS = v_safe + 6000 - 2000(occ only)            = v_safe + 4000
  IF (v_safe_after - v_safe) != 4000 THEN
    RAISE EXCEPTION 'T07 FAILED: Expected net STS change of +4000 (no double-count), got %',
      (v_safe_after - v_safe);
  END IF;

  RAISE NOTICE 'T07 PASSED: No double-counting for debts with occurrences';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T08: Safe-to-spend — PARTIALLY_PAID occurrence deducts only remaining
  -- Pay 500 of the 2000 first occurrence → occurrence remaining becomes 1500
  -- STS change: wallet -500 AND obligation -500 → net STS change = 0
  -- ═══════════════════════════════════════════════════════════════════════════
  SELECT id INTO v_occ_1_id
  FROM public.debt_due_occurrences
  WHERE debt_id = v_debt_id AND status = 'UPCOMING'
  ORDER BY sequence_no ASC LIMIT 1;

  v_safe := public.fn_calculate_safe_to_spend(v_family_id);

  PERFORM public.fn_record_debt_payment(
    p_family_id              => v_family_id,
    p_debt_id                => v_debt_id,
    p_amount                 => 500,
    p_wallet_id              => v_wallet_id,
    p_debt_due_occurrence_id => v_occ_1_id
  );

  v_safe_after := public.fn_calculate_safe_to_spend(v_family_id);

  -- wallet -500, obligation deduction -500 → net STS = 0 change
  IF v_safe_after != v_safe THEN
    RAISE EXCEPTION 'T08 FAILED: Partial payment STS mismatch. Before=%, After=%',
      v_safe, v_safe_after;
  END IF;

  RAISE NOTICE 'T08 PASSED: Partially-paid occurrence deducts only remaining';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T09: Safe-to-spend — legacy FLEXIBLE debt (no occurrences) uses next_due_date fallback
  -- Direct INSERT (bypass RPC) to simulate a legacy debt without occurrences
  -- ═══════════════════════════════════════════════════════════════════════════
  v_safe := public.fn_calculate_safe_to_spend(v_family_id);

  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.debts (
    family_id, entity_name, direction, original_amount, remaining_amount,
    status, created_by, debt_kind, payment_schedule_type,
    next_due_date, monthly_installment
  ) VALUES (
    v_family_id, 'T09 Legacy Flexible', 'BORROWED_FROM', 3000, 3000,
    'ACTIVE', v_member_id, 'PERSONAL', 'FLEXIBLE',
    CURRENT_DATE, 1000
  ) RETURNING id INTO v_debt_id;
  PERFORM set_config('role', 'authenticated', true);

  v_safe_after := public.fn_calculate_safe_to_spend(v_family_id);

  IF (v_safe - v_safe_after) != 1000 THEN
    RAISE EXCEPTION 'T09 FAILED: Legacy FLEXIBLE debt should deduct 1000, got deduction=%',
      (v_safe - v_safe_after);
  END IF;

  -- Cleanup direct insert
  PERFORM set_config('role', 'postgres', true);
  DELETE FROM public.debts WHERE id = v_debt_id;
  PERFORM set_config('role', 'authenticated', true);

  RAISE NOTICE 'T09 PASSED: Legacy flexible debt uses next_due_date fallback correctly';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T10: Settling a debt cancels remaining UPCOMING occurrences
  -- Use T07 debt (6000 original, 500 paid → remaining 5500)
  -- ═══════════════════════════════════════════════════════════════════════════
  SELECT remaining_amount INTO v_remaining FROM public.debts WHERE id = v_debt_id;

  -- Re-reference the T07 debt (last debt created via fn_receive_loan with 6000)
  SELECT id INTO v_debt_id
  FROM public.debts
  WHERE family_id = v_family_id
    AND entity_name = 'T07 No Double Count'
    AND status = 'ACTIVE';

  SELECT remaining_amount INTO v_remaining FROM public.debts WHERE id = v_debt_id;

  -- Pay everything remaining (free-form, no occurrence link)
  PERFORM public.fn_record_debt_payment(
    p_family_id => v_family_id,
    p_debt_id   => v_debt_id,
    p_amount    => v_remaining,
    p_wallet_id => v_wallet_id
  );

  SELECT status INTO v_status FROM public.debts WHERE id = v_debt_id;
  IF v_status != 'SETTLED' THEN
    RAISE EXCEPTION 'T10 FAILED: Debt should be SETTLED, got %', v_status;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.debt_due_occurrences
  WHERE debt_id = v_debt_id AND status IN ('UPCOMING', 'OVERDUE', 'PARTIALLY_PAID');

  IF v_count != 0 THEN
    RAISE EXCEPTION 'T10 FAILED: % remaining occurrences not cancelled after settlement', v_count;
  END IF;

  RAISE NOTICE 'T10 PASSED: Settlement cancels all remaining occurrences';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T11: Payroll deduction with occurrence — partial payment works correctly
  -- Debt: 4000 | 2 installments of 2000 | due today
  -- Payroll: income=5000, deduct=800 (partial)
  -- ═══════════════════════════════════════════════════════════════════════════
  SELECT debt_id INTO v_debt_id FROM public.fn_receive_loan(
    p_family_id             => v_family_id,
    p_entity_name           => 'T11 Work Advance',
    p_amount                => 4000,
    p_wallet_id             => v_wallet_id,
    p_debt_kind             => 'WORK_ADVANCE',
    p_payment_schedule_type => 'MONTHLY_INSTALLMENT',
    p_next_due_date         => CURRENT_DATE,
    p_monthly_installment   => 2000,
    p_installment_count     => 2
  );

  SELECT id INTO v_occ_1_id
  FROM public.debt_due_occurrences
  WHERE debt_id = v_debt_id AND status = 'UPCOMING'
  ORDER BY sequence_no ASC LIMIT 1;

  PERFORM public.fn_record_payroll_deducted_income(
    p_family_id              => v_family_id,
    p_total_income           => 5000,
    p_deducted_amount        => 800,
    p_wallet_id              => v_wallet_id,
    p_debt_id                => v_debt_id,
    p_category_id            => v_cat_id,
    p_debt_due_occurrence_id => v_occ_1_id
  );

  SELECT paid_amount, status INTO v_paid_amt, v_status
  FROM public.debt_due_occurrences WHERE id = v_occ_1_id;

  IF v_paid_amt != 800 THEN
    RAISE EXCEPTION 'T11 FAILED: paid_amount expected 800, got %', v_paid_amt;
  END IF;
  IF v_status != 'PARTIALLY_PAID' THEN
    RAISE EXCEPTION 'T11 FAILED: status expected PARTIALLY_PAID, got %', v_status;
  END IF;

  SELECT installments_paid INTO v_inst_paid FROM public.debts WHERE id = v_debt_id;
  IF v_inst_paid != 0 THEN
    RAISE EXCEPTION 'T11 FAILED: installments_paid should be 0 after partial payroll, got %', v_inst_paid;
  END IF;

  RAISE NOTICE 'T11 PASSED: Payroll deduction partial payment works with occurrence';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T12: fn_reschedule_debt regenerates occurrences from remaining amount
  -- T11 debt: 4000 original, 800 paid, remaining 3200
  -- Reschedule: 2 installments of 1600
  -- ═══════════════════════════════════════════════════════════════════════════
  SELECT remaining_amount INTO v_remaining FROM public.debts WHERE id = v_debt_id;

  PERFORM public.fn_reschedule_debt(
    p_family_id             => v_family_id,
    p_debt_id               => v_debt_id,
    p_payment_schedule_type => 'MONTHLY_INSTALLMENT',
    p_next_due_date         => CURRENT_DATE + 30,
    p_monthly_installment   => 1600,
    p_installment_count     => 2
  );

  SELECT COUNT(*) INTO v_count
  FROM public.debt_due_occurrences
  WHERE debt_id = v_debt_id AND status = 'UPCOMING';

  IF v_count != 2 THEN
    RAISE EXCEPTION 'T12 FAILED: Expected 2 UPCOMING occurrences after reschedule, got %', v_count;
  END IF;

  -- Verify new occurrences total equals remaining amount (3200)
  SELECT SUM(amount) INTO v_paid_amt   -- reusing variable for sum check
  FROM public.debt_due_occurrences
  WHERE debt_id = v_debt_id AND status = 'UPCOMING';

  IF v_paid_amt != v_remaining THEN
    RAISE EXCEPTION 'T12 FAILED: New occurrences total % != remaining %. Must cover full remaining balance',
      v_paid_amt, v_remaining;
  END IF;

  RAISE NOTICE 'T12 PASSED: fn_reschedule_debt regenerates occurrences from remaining amount';

  -- ── All tests passed — rollback to leave DB clean ──────────────────────────
  RAISE EXCEPTION 'TEST_SUCCESS_ROLLBACK';

EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', 'postgres', true);
  IF SQLERRM = 'TEST_SUCCESS_ROLLBACK' THEN
    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'ALL 12 TESTS PASSED — 00045_borrowed_debt_obligations.test.sql';
    RAISE NOTICE '=============================================================';
  ELSE
    RAISE;
  END IF;
END $$;
