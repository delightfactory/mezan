BEGIN;
SELECT plan(8);

-- Setup Data
INSERT INTO public.family_groups(id, name) VALUES ('e0000000-0000-0000-0000-000000000000', 'Test Family');
INSERT INTO auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at) VALUES 
  ('e1000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@test.com', 'pwd', now(), now(), now()),
  ('e2000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'member@test.com', 'pwd', now(), now(), now()),
  ('e3000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'viewer@test.com', 'pwd', now(), now(), now());

INSERT INTO public.family_members(id, family_id, user_id, role, status) VALUES 
  ('f1000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'e1000000-0000-0000-0000-000000000000', 'OWNER', 'ACTIVE'),
  ('f2000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'e2000000-0000-0000-0000-000000000000', 'MEMBER', 'ACTIVE'),
  ('f3000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'e3000000-0000-0000-0000-000000000000', 'VIEWER', 'ACTIVE');

INSERT INTO public.wallets(id, family_id, name, type, balance) VALUES 
  ('a1000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'Wallet', 'REAL', 5000);

INSERT INTO public.categories(id, family_id, name_ar, direction, is_system, behavior) VALUES 
  ('c1000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'Salary', 'INCOME', false, 'FIXED_ESSENTIAL');


-- 1. Test Safe to Spend before debt
SELECT is(
  public.fn_calculate_safe_to_spend('e0000000-0000-0000-0000-000000000000'),
  5000.00,
  'Safe to spend should initially be wallet balance (5000)'
);

-- Set to Authenticated Owner
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"e1000000-0000-0000-0000-000000000000"}', true);

-- 2. Test direct INSERT blocked
SELECT throws_ok(
  $$ INSERT INTO public.debts(family_id, entity_name, direction, original_amount, remaining_amount, created_by) VALUES ('e0000000-0000-0000-0000-000000000000', 'Direct', 'BORROWED_FROM', 100, 100, 'f1000000-0000-0000-0000-000000000000') $$,
  'new row violates row-level security policy for table "debts"',
  'Direct insert on debts table should fail due to RLS'
);

-- 3. Create a debt via RPC
SELECT lives_ok(
  $$ SELECT public.fn_receive_loan('e0000000-0000-0000-0000-000000000000', 'Ahmed', 1000, 'a1000000-0000-0000-0000-000000000000', now(), 'PERSONAL', 'MONTHLY_INSTALLMENT', CURRENT_DATE, CURRENT_DATE, 200, 5) $$,
  'OWNER can receive a loan via RPC'
);

-- 4. Test Safe to Spend deducts active debt installment
SELECT is(
  public.fn_calculate_safe_to_spend('e0000000-0000-0000-0000-000000000000'),
  5800.00,
  'Safe to spend should be 6000 (Wallet) - 200 (Active Debt Installment due this month) = 5800'
);

-- 5. Test direct UPDATE blocked (Using a function to check rows affected)
CREATE OR REPLACE FUNCTION pg_temp.test_direct_update() RETURNS INT AS $$
DECLARE v_did UUID; r INT;
BEGIN
  SELECT id INTO v_did FROM public.debts LIMIT 1;
  UPDATE public.debts SET remaining_amount = 0 WHERE id = v_did;
  GET DIAGNOSTICS r = ROW_COUNT;
  RETURN r;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

SELECT is(
  pg_temp.test_direct_update(),
  0,
  'Direct UPDATE on debts should affect 0 rows because of RLS restrictions'
);

-- 6. Verify with postgres role that data did not change
RESET ROLE;
SELECT is(
  (SELECT remaining_amount FROM public.debts LIMIT 1),
  1000.00,
  'remaining_amount should still be 1000, proving direct update failed'
);

-- Switch back to OWNER
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"e1000000-0000-0000-0000-000000000000"}', true);

-- 7. Test VIEWER access to write-off (should fail)
SELECT set_config('request.jwt.claims', '{"sub":"e3000000-0000-0000-0000-000000000000"}', true);
SELECT throws_ok(
  $$ SELECT public.fn_write_off_debt('e0000000-0000-0000-0000-000000000000', (SELECT id FROM public.debts LIMIT 1), 'TEST') $$,
  'ACCESS_DENIED',
  'VIEWER cannot write-off debt'
);

-- 8. Test successful payroll deduction
SELECT set_config('request.jwt.claims', '{"sub":"e1000000-0000-0000-0000-000000000000"}', true);
SELECT lives_ok(
  $$ SELECT public.fn_record_payroll_deducted_income(
    'e0000000-0000-0000-0000-000000000000',
    2000, 200, 'a1000000-0000-0000-0000-000000000000',
    (SELECT id FROM public.debts LIMIT 1), 'c1000000-0000-0000-0000-000000000000'
  ) $$,
  'OWNER can record payroll deducted income successfully'
);

SELECT * FROM finish();
ROLLBACK;
