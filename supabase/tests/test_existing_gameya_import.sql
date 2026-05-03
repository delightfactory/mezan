BEGIN;

SELECT plan(12);

-- 1. Setup Data
INSERT INTO auth.users (id, email) VALUES ('00000000-0000-0000-0000-000000000001'::uuid, 'test_import@example.com') ON CONFLICT DO NOTHING;
INSERT INTO public.family_groups (id, name) VALUES ('11111111-1111-1111-1111-111111111111'::uuid, 'Test Import Family') ON CONFLICT DO NOTHING;
INSERT INTO public.family_members (id, family_id, user_id, role) VALUES ('22222222-2222-2222-2222-222222222222'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, 'OWNER') ON CONFLICT DO NOTHING;

INSERT INTO public.wallets (id, family_id, name, type, balance, created_by)
VALUES ('33333333-3333-3333-3333-333333333333'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'Cash', 'REAL', 10000, '22222222-2222-2222-2222-222222222222'::uuid) ON CONFLICT DO NOTHING;

SELECT set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001"}', true);

-- Call the RPC directly and store result in temporary table
CREATE TEMP TABLE temp_gameyas AS 
SELECT public.fn_import_existing_gameya_circle(
    '11111111-1111-1111-1111-111111111111'::uuid,
    'Gameya 4 Paid'::text,
    1000::numeric,
    'MONTHLY'::public.gameya_payment_frequency,
    'MONTHLY'::public.gameya_turn_frequency,
    10,
    10,
    (CURRENT_DATE - INTERVAL '4 months')::date,
    CURRENT_DATE,
    4,
    false,
    0::numeric,
    0::numeric
  ) as g1_id,
  public.fn_import_existing_gameya_circle(
    '11111111-1111-1111-1111-111111111111'::uuid,
    'Gameya 2 Paid 2 Overdue'::text,
    1000::numeric,
    'MONTHLY'::public.gameya_payment_frequency,
    'MONTHLY'::public.gameya_turn_frequency,
    10,
    10,
    (CURRENT_DATE - INTERVAL '4 months')::date,
    CURRENT_DATE,
    2,
    false,
    0::numeric,
    0::numeric
  ) as g2_id,
  public.fn_import_existing_gameya_circle(
    '11111111-1111-1111-1111-111111111111'::uuid,
    'Gameya Payout Received'::text,
    1000::numeric,
    'MONTHLY'::public.gameya_payment_frequency,
    'MONTHLY'::public.gameya_turn_frequency,
    10,
    2,
    (CURRENT_DATE - INTERVAL '4 months')::date,
    CURRENT_DATE,
    4,
    true,
    10000::numeric,
    6000::numeric
  ) as g3_id;

-- Case 1 Tests
SELECT results_eq(
    'SELECT balance::int FROM public.wallets WHERE id = (SELECT wallet_id FROM public.gameya_circles WHERE id = (SELECT g1_id FROM temp_gameyas))',
    ARRAY[4000],
    'Case 1: Allocated wallet balance should be 4000 for 4 paid installments'
);

SELECT results_eq(
    'SELECT amount::int FROM public.ledger_transactions WHERE to_wallet_id = (SELECT wallet_id FROM public.gameya_circles WHERE id = (SELECT g1_id FROM temp_gameyas)) AND type = ''OPENING_BALANCE''',
    ARRAY[4000],
    'Case 1: Ledger transaction OPENING_BALANCE should exist with 4000'
);

SELECT results_eq(
    'SELECT COUNT(*)::int FROM public.gameya_installments WHERE gameya_id = (SELECT g1_id FROM temp_gameyas) AND status = ''PAID'' AND transaction_id IS NOT NULL',
    ARRAY[4],
    'Case 1: 4 installments should be PAID and linked to transaction'
);

-- Case 2 Tests
SELECT results_eq(
    'SELECT balance::int FROM public.wallets WHERE id = (SELECT wallet_id FROM public.gameya_circles WHERE id = (SELECT g2_id FROM temp_gameyas))',
    ARRAY[2000],
    'Case 2: Allocated wallet balance should be 2000 for 2 paid installments'
);

SELECT results_eq(
    'SELECT COUNT(*)::int FROM public.gameya_installments WHERE gameya_id = (SELECT g2_id FROM temp_gameyas) AND status = ''PAID''',
    ARRAY[2],
    'Case 2: 2 installments should be PAID'
);

SELECT results_eq(
    'SELECT COUNT(*)::int FROM public.gameya_installments WHERE gameya_id = (SELECT g2_id FROM temp_gameyas) AND status = ''OVERDUE''',
    ARRAY[2],
    'Case 2: 2 past unpaid installments should be OVERDUE explicitly'
);

-- Case 3 Tests
SELECT is(
    (SELECT payout_debt_id IS NOT NULL FROM public.gameya_circles WHERE id = (SELECT g3_id FROM temp_gameyas)),
    true,
    'Case 3: payout_debt_id should be set'
);

SELECT results_eq(
    'SELECT remaining_amount::int FROM public.debts WHERE id = (SELECT payout_debt_id FROM public.gameya_circles WHERE id = (SELECT g3_id FROM temp_gameyas))',
    ARRAY[6000],
    'Case 3: Debt should be created with remaining amount 6000'
);

SELECT results_eq(
    'SELECT COUNT(*)::int FROM public.gameya_installments WHERE gameya_id = (SELECT g3_id FROM temp_gameyas) AND status = ''CANCELLED''',
    ARRAY[6],
    'Case 3: Unpaid installments should be CANCELLED to prevent double counting'
);

SELECT results_eq(
    'SELECT COUNT(*)::int FROM public.gameya_installments WHERE gameya_id = (SELECT g3_id FROM temp_gameyas) AND status IN (''UPCOMING'', ''OVERDUE'')',
    ARRAY[0],
    'Case 3: No UPCOMING or OVERDUE installments should exist for received payout gameya'
);

-- Direct Wallet Mutation Tests
SELECT results_eq(
    'SELECT balance::int FROM public.wallets WHERE id = (SELECT wallet_id FROM public.gameya_circles WHERE id = (SELECT g1_id FROM temp_gameyas))',
    'SELECT SUM(amount)::int FROM public.ledger_transactions WHERE to_wallet_id = (SELECT wallet_id FROM public.gameya_circles WHERE id = (SELECT g1_id FROM temp_gameyas))',
    'Allocated Wallet 1 balance should exactly match its ledger transactions'
);

SELECT results_eq(
    'SELECT balance::int FROM public.wallets WHERE id = (SELECT wallet_id FROM public.gameya_circles WHERE id = (SELECT g2_id FROM temp_gameyas))',
    'SELECT SUM(amount)::int FROM public.ledger_transactions WHERE to_wallet_id = (SELECT wallet_id FROM public.gameya_circles WHERE id = (SELECT g2_id FROM temp_gameyas))',
    'Allocated Wallet 2 balance should exactly match its ledger transactions'
);

SELECT * FROM finish();
ROLLBACK;
