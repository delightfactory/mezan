BEGIN;
DO $$
BEGIN
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.fn_create_initial_family('عائلة تجريبية');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE NOTICE 'Caught: %', SQLERRM;
  END;
  RESET ROLE;
END $$;
ROLLBACK;
