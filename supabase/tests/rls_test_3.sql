BEGIN;
SET LOCAL ROLE authenticated;
UPDATE public.wallets SET balance = 9999 WHERE type = 'REAL';
ROLLBACK;
