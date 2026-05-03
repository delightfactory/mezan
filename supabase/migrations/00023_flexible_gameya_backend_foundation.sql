-- =============================================================================
-- Mezan: 00023_flexible_gameya_backend_foundation.sql
-- Phase 7B: Flexible Gameya Backend Foundation
-- =============================================================================

-- 1. Enums
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'gameya_payment_frequency') THEN
    CREATE TYPE public.gameya_payment_frequency AS ENUM ('DAILY', 'WEEKLY', 'BIWEEKLY', 'SEMI_MONTHLY', 'MONTHLY');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'gameya_turn_frequency') THEN
    CREATE TYPE public.gameya_turn_frequency AS ENUM ('WEEKLY', 'BIWEEKLY', 'SEMI_MONTHLY', 'MONTHLY');
  END IF;
END $$;

-- 2. Columns on gameya_circles
ALTER TABLE public.gameya_circles
ADD COLUMN IF NOT EXISTS installment_amount NUMERIC(14,2),
ADD COLUMN IF NOT EXISTS payment_frequency public.gameya_payment_frequency,
ADD COLUMN IF NOT EXISTS turn_frequency public.gameya_turn_frequency,
ADD COLUMN IF NOT EXISTS total_turns INT,
ADD COLUMN IF NOT EXISTS payout_turn INT,
ADD COLUMN IF NOT EXISTS expected_payout_date DATE,
ADD COLUMN IF NOT EXISTS flex_payout_amount NUMERIC(14,2),
ADD COLUMN IF NOT EXISTS is_flexible BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS legacy_migrated_at TIMESTAMPTZ;

-- 3. New table gameya_installments
CREATE TABLE IF NOT EXISTS public.gameya_installments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gameya_id UUID NOT NULL REFERENCES public.gameya_circles(id) ON DELETE CASCADE,
  family_id UUID NOT NULL REFERENCES public.family_groups(id) ON DELETE CASCADE,
  installment_number INT NOT NULL,
  due_date DATE NOT NULL,
  amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  status public.occurrence_status NOT NULL DEFAULT 'UPCOMING',
  transaction_id UUID REFERENCES public.ledger_transactions(id) ON DELETE SET NULL,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  UNIQUE(gameya_id, installment_number)
);

CREATE INDEX IF NOT EXISTS idx_gameya_install_family_due_status ON public.gameya_installments(family_id, due_date, status);
CREATE INDEX IF NOT EXISTS idx_gameya_install_gameya_due ON public.gameya_installments(gameya_id, due_date);
CREATE INDEX IF NOT EXISTS idx_gameya_install_gameya_status ON public.gameya_installments(gameya_id, status);

-- 4. RLS for gameya_installments
ALTER TABLE public.gameya_installments ENABLE ROW LEVEL SECURITY;

-- Read policy only. No INSERT, UPDATE, or DELETE from client.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'gameya_installments' AND policyname = 'view_gameya_installments'
  ) THEN
    CREATE POLICY "view_gameya_installments" ON public.gameya_installments
    FOR SELECT TO authenticated
    USING (
      family_id IN (SELECT public.get_my_family_ids())
    );
  END IF;
END $$;

-- 5. Backfill legacy gameyas
-- 5.a Create installments from existing turns
INSERT INTO public.gameya_installments (
  gameya_id, family_id, installment_number, due_date, amount, status, transaction_id, paid_at
)
SELECT 
  t.gameya_id,
  t.family_id,
  t.turn_number,
  t.due_date,
  c.monthly_installment,
  CASE 
    WHEN t.status = 'PAID' THEN 'PAID'::public.occurrence_status
    WHEN t.status = 'MISSED' THEN 'OVERDUE'::public.occurrence_status
    WHEN t.status = 'UPCOMING' THEN 'UPCOMING'::public.occurrence_status
    WHEN t.status = 'RECEIVED' THEN 
       CASE WHEN t.transaction_id IS NOT NULL THEN 'PAID'::public.occurrence_status ELSE 'UPCOMING'::public.occurrence_status END
  END,
  t.transaction_id,
  t.paid_at
FROM public.gameya_turns t
JOIN public.gameya_circles c ON c.id = t.gameya_id
ON CONFLICT (gameya_id, installment_number) DO NOTHING;

-- 5.b Migrate legacy circles that now have installments
UPDATE public.gameya_circles c
SET 
  installment_amount = monthly_installment,
  payment_frequency = 'MONTHLY'::public.gameya_payment_frequency,
  turn_frequency = 'MONTHLY'::public.gameya_turn_frequency,
  total_turns = total_months,
  payout_turn = payout_month,
  expected_payout_date = (start_date + make_interval(months => payout_month - 1))::date,
  flex_payout_amount = payout_amount,
  is_flexible = false,
  legacy_migrated_at = NOW()
WHERE EXISTS (
  SELECT 1 FROM public.gameya_installments i WHERE i.gameya_id = c.id
) AND legacy_migrated_at IS NULL;

-- 6. Safe-to-spend update
CREATE OR REPLACE FUNCTION public.fn_calculate_safe_to_spend(p_family_id UUID)
RETURNS NUMERIC(14,2) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_real NUMERIC(14,2);
  v_commits NUMERIC(14,2);
  v_debts NUMERIC(14,2);
  v_gameya NUMERIC(14,2);
  v_gameya_flex NUMERIC(14,2);
  v_gameya_legacy NUMERIC(14,2);
  v_end_of_month DATE;
BEGIN
  PERFORM public._require_member(p_family_id, ARRAY['OWNER','MEMBER','VIEWER']::public.member_role[]);
  
  v_end_of_month := (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date;

  SELECT COALESCE(SUM(balance),0) INTO v_real 
  FROM public.wallets 
  WHERE family_id = p_family_id AND type = 'REAL' AND NOT is_archived;

  SELECT COALESCE(SUM(amount),0) INTO v_commits 
  FROM public.commitment_occurrences 
  WHERE family_id = p_family_id 
    AND status IN ('UPCOMING','OVERDUE')
    AND due_date <= v_end_of_month;

  SELECT COALESCE(SUM(
    CASE
      WHEN monthly_installment IS NOT NULL AND monthly_installment > 0
        THEN LEAST(monthly_installment, remaining_amount)
      WHEN (monthly_installment IS NULL OR monthly_installment = 0)
        AND due_date IS NOT NULL
        AND due_date <= v_end_of_month
        THEN remaining_amount
      ELSE 0
    END
  ), 0) INTO v_debts
  FROM public.debts
  WHERE family_id = p_family_id
    AND status = 'ACTIVE'
    AND direction = 'BORROWED_FROM';

  -- Upcoming gameya installments due in current cycle (New Logic)
  SELECT COALESCE(SUM(i.amount), 0) INTO v_gameya_flex
  FROM public.gameya_installments i
  WHERE i.family_id = p_family_id
    AND i.status IN ('UPCOMING', 'OVERDUE')
    AND i.due_date <= v_end_of_month;

  -- Upcoming gameya turns due in current cycle (Legacy Logic fallback)
  SELECT COALESCE(SUM(c.monthly_installment), 0) INTO v_gameya_legacy
  FROM public.gameya_turns t
  JOIN public.gameya_circles c ON t.gameya_id = c.id
  WHERE t.family_id = p_family_id
    AND t.status IN ('UPCOMING', 'MISSED')
    AND t.due_date <= v_end_of_month
    AND NOT EXISTS (
      SELECT 1 FROM public.gameya_installments i WHERE i.gameya_id = c.id
    );

  v_gameya := v_gameya_flex + v_gameya_legacy;

  RETURN GREATEST(v_real - v_commits - v_debts - v_gameya, 0);
END; $$;

-- 7. Grants
REVOKE ALL ON FUNCTION public.fn_calculate_safe_to_spend(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_calculate_safe_to_spend(UUID) TO authenticated;
