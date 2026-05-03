BEGIN;
DO $$
BEGIN
  BEGIN
    SET LOCAL ROLE anon;
    -- Just raise an exception and catch it
    RAISE EXCEPTION 'Just an error';
  EXCEPTION
    WHEN OTHERS THEN
      RAISE NOTICE 'Caught: %', SQLERRM;
  END;
  RESET ROLE;
END $$;
ROLLBACK;
