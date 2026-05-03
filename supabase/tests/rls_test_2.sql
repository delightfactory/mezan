BEGIN;
SET LOCAL ROLE anon;
SELECT public.fn_create_initial_family('عائلة تجريبية');
ROLLBACK;
