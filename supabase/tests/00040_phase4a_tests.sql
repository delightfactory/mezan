BEGIN;
SELECT plan(12);

-- Setup Data
INSERT INTO public.family_groups(id, name) VALUES ('e0000000-0000-0000-0000-000000000000', 'Test Family');
INSERT INTO auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at) VALUES 
  ('e1000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@test.com', 'pwd', now(), now(), now()),
  ('e2000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'suspended@test.com', 'pwd', now(), now(), now());

INSERT INTO public.family_members(id, family_id, user_id, role, status) VALUES 
  ('f1000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'e1000000-0000-0000-0000-000000000000', 'OWNER', 'ACTIVE'),
  ('f2000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'e2000000-0000-0000-0000-000000000000', 'MEMBER', 'SUSPENDED');

INSERT INTO public.wallets(id, family_id, name, type, balance) VALUES 
  ('a1000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'Wallet', 'REAL', 10000);

INSERT INTO public.categories(id, family_id, name_ar, direction, is_system, behavior) VALUES 
  ('c1000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'Housing', 'EXPENSE', false, 'FIXED_ESSENTIAL');

-- 1. Test no overload for fn_pay_commitment_occurrence
SELECT is(
  (SELECT count(*)::int
   FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public' 
     AND p.proname = 'fn_pay_commitment_occurrence'),
  1,
  'There should be exactly 1 definition for fn_pay_commitment_occurrence (no old overloads)'
);

-- Set to Authenticated Owner
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"e1000000-0000-0000-0000-000000000000"}', true);

-- Setup Commitment
INSERT INTO public.commitments (id, family_id, name, amount, frequency, start_date, wallet_id, category_id, priority_level) 
VALUES ('c0000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'Rent', 1000, 'MONTHLY', CURRENT_DATE, 'a1000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000000', 1);

INSERT INTO public.commitment_occurrences (id, commitment_id, family_id, amount, due_date, status) 
VALUES ('b0000000-0000-0000-0000-000000000000', 'c0000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 1000, CURRENT_DATE, 'UPCOMING');

-- 2. Partial Payment makes status PARTIALLY_PAID and updates paid_amount
SELECT lives_ok(
  $$ SELECT public.fn_pay_commitment_occurrence('e0000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000000', 400, now(), 'Partial Payment') $$,
  'OWNER can make a partial payment on commitment'
);

SELECT is(
  (SELECT status FROM public.commitment_occurrences WHERE id = 'b0000000-0000-0000-0000-000000000000'),
  'PARTIALLY_PAID'::public.occurrence_status,
  'Occurrence status should be PARTIALLY_PAID'
);

SELECT is(
  (SELECT paid_amount FROM public.commitment_occurrences WHERE id = 'b0000000-0000-0000-0000-000000000000'),
  400.00,
  'paid_amount should be 400.00'
);

-- 3. Overpayment is rejected
SELECT throws_ok(
  $$ SELECT public.fn_pay_commitment_occurrence('e0000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000000', 700, now(), 'Overpayment') $$,
  'OVERPAYMENT_NOT_ALLOWED',
  'Paying more than remaining amount (700 > 600) should throw OVERPAYMENT_NOT_ALLOWED'
);

RESET ROLE;
-- Setup Active Debt
INSERT INTO public.debts (id, family_id, entity_name, direction, original_amount, remaining_amount, created_by, status, due_date, next_due_date, payment_schedule_type)
VALUES ('d0000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'Lender', 'BORROWED_FROM', 2000, 2000, 'f1000000-0000-0000-0000-000000000000', 'ACTIVE', CURRENT_DATE, CURRENT_DATE, 'ONE_TIME');

-- Setup Gameya
INSERT INTO public.gameya_circles (id, family_id, name, monthly_installment, payment_frequency, turn_frequency, total_months, start_date, is_flexible, status, payout_month, payout_turn) 
VALUES ('a2000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 'Gameya', 500, 'MONTHLY', 'MONTHLY', 10, CURRENT_DATE, true, 'SAVING_PHASE', 5, 5);

INSERT INTO public.gameya_installments (id, gameya_id, family_id, amount, due_date, status, installment_number) 
VALUES ('a3000000-0000-0000-0000-000000000000', 'a2000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000000', 500, CURRENT_DATE, 'UPCOMING', 1);

-- Switch back to OWNER
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"e1000000-0000-0000-0000-000000000000"}', true);

-- 4. Safe to spend calculation
-- Real wallet: 10000 - 400 (paid) = 9600
-- Remaining commit: 600
-- Debt remaining: 2000
-- Gameya remaining: 500
-- Safe: 9600 - 600 - 2000 - 500 = 6500
SELECT is(
  public.fn_calculate_safe_to_spend('e0000000-0000-0000-0000-000000000000'),
  6500.00,
  'Safe to spend should deduct remaining commitment (600), debts (2000), and gameya (500)'
);

-- 5. Pay Remaining makes status PAID
SELECT lives_ok(
  $$ SELECT public.fn_pay_commitment_occurrence('e0000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000000', 600, now(), 'Rest Payment') $$,
  'OWNER can pay the remaining amount'
);

SELECT is(
  (SELECT status FROM public.commitment_occurrences WHERE id = 'b0000000-0000-0000-0000-000000000000'),
  'PAID'::public.occurrence_status,
  'Occurrence status should be PAID after full payment'
);

SELECT is(
  (SELECT paid_amount FROM public.commitment_occurrences WHERE id = 'b0000000-0000-0000-0000-000000000000'),
  1000.00,
  'paid_amount should equal total amount (1000.00)'
);

SELECT is(
  public.fn_calculate_safe_to_spend('e0000000-0000-0000-0000-000000000000'),
  6500.00,
  'Safe to spend remains the same after paying the rest (wallet decreased by 600, liability decreased by 600)'
);

-- 6. RLS prevents SUSPENDED user from reading commitment_payments
SELECT set_config('request.jwt.claims', '{"sub":"e2000000-0000-0000-0000-000000000000"}', true);

SELECT is(
  (SELECT count(*)::int FROM public.commitment_payments WHERE family_id = 'e0000000-0000-0000-0000-000000000000'),
  0,
  'SUSPENDED member should read 0 rows from commitment_payments due to RLS'
);

-- Ensure OWNER can read
SELECT set_config('request.jwt.claims', '{"sub":"e1000000-0000-0000-0000-000000000000"}', true);
SELECT is(
  (SELECT count(*)::int FROM public.commitment_payments WHERE family_id = 'e0000000-0000-0000-0000-000000000000'),
  2,
  'OWNER should read the 2 partial payments from commitment_payments'
);

SELECT * FROM finish();
ROLLBACK;
