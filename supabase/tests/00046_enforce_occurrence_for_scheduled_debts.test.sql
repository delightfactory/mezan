-- =============================================================================
-- Mezan: 00046_enforce_occurrence_for_scheduled_debts.test.sql
-- Tests for the DEBT_OCCURRENCE_REQUIRED guard in fn_record_debt_payment
-- and fn_record_payroll_deducted_income (migration 00046).
--
-- T01 - Free-form payment on MONTHLY_INSTALLMENT debt REJECTED (DEBT_OCCURRENCE_REQUIRED)
-- T02 - Free-form payment on FLEXIBLE debt ALLOWED (no occurrences)
-- T03 - Payroll deduction on scheduled debt without occurrence REJECTED
-- T04 - Payroll deduction on scheduled debt WITH occurrence ACCEPTED
-- T05 - LENT_TO debt: free-form payment ALLOWED (guard only applies to BORROWED_FROM)
-- =============================================================================

DO $$
DECLARE
  v_user_id   UUID := gen_random_uuid();
  v_family_id UUID;
  v_member_id UUID;
  v_wallet_id UUID;
  v_cat_id    UUID;
  v_debt_sched UUID;  -- MONTHLY_INSTALLMENT debt
  v_debt_flex  UUID;  -- FLEXIBLE debt
  v_debt_lent  UUID;  -- LENT_TO debt
  v_occ_id    UUID;
BEGIN
  -- ── Setup ─────────────────────────────────────────────────────────────────
  INSERT INTO auth.users (id, email, aud, role, encrypted_password, created_at, updated_at)
  VALUES (v_user_id, 'test46_' || v_user_id || '@mezan.test',
    'authenticated', 'authenticated', 'test-hash', now(), now());

  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_user_id)::text, true);
  PERFORM set_config('role', 'authenticated', true);

  SELECT family_id, member_id INTO v_family_id, v_member_id
  FROM public.fn_create_initial_family('Test 46 Family', 'Test Owner');

  INSERT INTO public.wallets (family_id, name, type, balance, created_by)
  VALUES (v_family_id, 'Main Wallet', 'REAL', 100000, v_member_id)
  RETURNING id INTO v_wallet_id;

  INSERT INTO public.categories (family_id, name_ar, name_en, direction, is_system, behavior)
  VALUES (v_family_id, 'مرتب', 'Salary', 'INCOME', false, 'FIXED_ESSENTIAL')
  RETURNING id INTO v_cat_id;

  -- Create MONTHLY_INSTALLMENT debt (will have occurrences)
  SELECT debt_id INTO v_debt_sched FROM public.fn_receive_loan(
    p_family_id             => v_family_id,
    p_entity_name           => 'T01 Scheduled Loan',
    p_amount                => 3000,
    p_wallet_id             => v_wallet_id,
    p_payment_schedule_type => 'MONTHLY_INSTALLMENT',
    p_next_due_date         => CURRENT_DATE,
    p_monthly_installment   => 1000,
    p_installment_count     => 3
  );

  -- Create FLEXIBLE debt (no occurrences)
  SELECT debt_id INTO v_debt_flex FROM public.fn_receive_loan(
    p_family_id             => v_family_id,
    p_entity_name           => 'T02 Flexible Loan',
    p_amount                => 2000,
    p_wallet_id             => v_wallet_id,
    p_payment_schedule_type => 'FLEXIBLE'
  );

  -- Create LENT_TO debt (free-form always allowed)
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.debts (
    family_id, entity_name, direction, original_amount, remaining_amount,
    status, created_by, debt_kind, payment_schedule_type
  ) VALUES (
    v_family_id, 'T05 Lent Debt', 'LENT_TO', 1000, 1000,
    'ACTIVE', v_member_id, 'PERSONAL', 'MONTHLY_INSTALLMENT'
  ) RETURNING id INTO v_debt_lent;
  PERFORM set_config('role', 'authenticated', true);

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T01: Free-form payment on MONTHLY_INSTALLMENT BORROWED_FROM → REJECTED
  -- ═══════════════════════════════════════════════════════════════════════════
  BEGIN
    PERFORM public.fn_record_debt_payment(
      p_family_id => v_family_id,
      p_debt_id   => v_debt_sched,
      p_amount    => 500,
      p_wallet_id => v_wallet_id
      -- p_debt_due_occurrence_id intentionally omitted
    );
    RAISE EXCEPTION 'T01 FAILED: Free-form payment on scheduled debt was NOT rejected';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'T01 FAILED: Free-form payment on scheduled debt was NOT rejected' THEN RAISE; END IF;
    IF SQLERRM NOT ILIKE '%DEBT_OCCURRENCE_REQUIRED%' THEN
      RAISE EXCEPTION 'T01 FAILED: Wrong exception: %', SQLERRM;
    END IF;
  END;
  RAISE NOTICE 'T01 PASSED: Free-form payment rejected with DEBT_OCCURRENCE_REQUIRED';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T02: Free-form payment on FLEXIBLE debt → ALLOWED
  -- ═══════════════════════════════════════════════════════════════════════════
  PERFORM public.fn_record_debt_payment(
    p_family_id => v_family_id,
    p_debt_id   => v_debt_flex,
    p_amount    => 500,
    p_wallet_id => v_wallet_id
  );
  RAISE NOTICE 'T02 PASSED: Free-form payment on FLEXIBLE debt accepted';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T03: Payroll deduction on scheduled debt without occurrence → REJECTED
  -- ═══════════════════════════════════════════════════════════════════════════
  BEGIN
    PERFORM public.fn_record_payroll_deducted_income(
      p_family_id       => v_family_id,
      p_total_income    => 5000,
      p_deducted_amount => 1000,
      p_wallet_id       => v_wallet_id,
      p_debt_id         => v_debt_sched,
      p_category_id     => v_cat_id
      -- p_debt_due_occurrence_id intentionally omitted
    );
    RAISE EXCEPTION 'T03 FAILED: Payroll without occurrence was NOT rejected';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'T03 FAILED: Payroll without occurrence was NOT rejected' THEN RAISE; END IF;
    IF SQLERRM NOT ILIKE '%DEBT_OCCURRENCE_REQUIRED%' THEN
      RAISE EXCEPTION 'T03 FAILED: Wrong exception: %', SQLERRM;
    END IF;
  END;
  RAISE NOTICE 'T03 PASSED: Payroll without occurrence rejected with DEBT_OCCURRENCE_REQUIRED';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T04: Payroll deduction WITH occurrence → ACCEPTED
  -- ═══════════════════════════════════════════════════════════════════════════
  SELECT id INTO v_occ_id
  FROM public.debt_due_occurrences
  WHERE debt_id = v_debt_sched AND status = 'UPCOMING'
  ORDER BY sequence_no ASC LIMIT 1;

  PERFORM public.fn_record_payroll_deducted_income(
    p_family_id              => v_family_id,
    p_total_income           => 5000,
    p_deducted_amount        => 600,
    p_wallet_id              => v_wallet_id,
    p_debt_id                => v_debt_sched,
    p_category_id            => v_cat_id,
    p_debt_due_occurrence_id => v_occ_id
  );

  DECLARE v_status TEXT; v_paid NUMERIC;
  BEGIN
    SELECT status, paid_amount INTO v_status, v_paid
    FROM public.debt_due_occurrences WHERE id = v_occ_id;
    IF v_status != 'PARTIALLY_PAID' THEN
      RAISE EXCEPTION 'T04 FAILED: occurrence status expected PARTIALLY_PAID, got %', v_status;
    END IF;
    IF v_paid != 600 THEN
      RAISE EXCEPTION 'T04 FAILED: paid_amount expected 600, got %', v_paid;
    END IF;
  END;
  RAISE NOTICE 'T04 PASSED: Payroll with occurrence accepted and occurrence updated';

  -- ═══════════════════════════════════════════════════════════════════════════
  -- T05: LENT_TO debt — free-form payment ALLOWED (guard skips LENT_TO)
  -- ═══════════════════════════════════════════════════════════════════════════
  PERFORM public.fn_record_debt_payment(
    p_family_id => v_family_id,
    p_debt_id   => v_debt_lent,
    p_amount    => 500,
    p_wallet_id => v_wallet_id
  );
  RAISE NOTICE 'T05 PASSED: LENT_TO free-form payment accepted';

  -- ── Rollback to leave DB clean ────────────────────────────────────────────
  RAISE EXCEPTION 'TEST_SUCCESS_ROLLBACK';

EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('role', 'postgres', true);
  IF SQLERRM = 'TEST_SUCCESS_ROLLBACK' THEN
    RAISE NOTICE '======================================================';
    RAISE NOTICE 'ALL 5 TESTS PASSED — 00046 occurrence guard tests';
    RAISE NOTICE '======================================================';
  ELSE
    RAISE;
  END IF;
END $$;
