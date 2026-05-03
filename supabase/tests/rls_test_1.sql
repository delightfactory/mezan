BEGIN;
SET LOCAL ROLE authenticated;
INSERT INTO public.family_groups (name) VALUES ('اختراق');
ROLLBACK;
