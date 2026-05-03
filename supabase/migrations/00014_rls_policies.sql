-- =============================================================================
-- Mezan: 00014_rls_policies.sql
-- Row Level Security on ALL public tables.
-- Pattern: membership verified via family_members join on auth.uid().
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper: returns family IDs where current user is an active member.
-- SECURITY DEFINER so it can read family_members regardless of RLS on that table.
-- Strict search_path for safety.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_family_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT family_id
  FROM public.family_members
  WHERE user_id = (SELECT auth.uid())
    AND status = 'ACTIVE';
$$;

-- Helper: check if current user has a specific role in a family.
CREATE OR REPLACE FUNCTION public.user_has_role(p_family_id UUID, p_roles public.member_role[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.family_members
    WHERE user_id = (SELECT auth.uid())
      AND family_id = p_family_id
      AND status = 'ACTIVE'
      AND role = ANY(p_roles)
  );
$$;

REVOKE ALL ON FUNCTION public.get_my_family_ids() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_family_ids() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_family_ids() TO authenticated;

REVOKE ALL ON FUNCTION public.user_has_role(UUID, public.member_role[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.user_has_role(UUID, public.member_role[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.user_has_role(UUID, public.member_role[]) TO authenticated;

-- ==========================================================================
-- 1. family_groups
-- ==========================================================================
ALTER TABLE public.family_groups ENABLE ROW LEVEL SECURITY;

CREATE POLICY family_groups_select ON public.family_groups
  FOR SELECT USING (id IN (SELECT public.get_my_family_ids()));

-- Direct inserts disabled to enforce RPC-only creation

CREATE POLICY family_groups_update ON public.family_groups
  FOR UPDATE USING (
    public.user_has_role(id, ARRAY['OWNER']::public.member_role[])
  );

-- No delete policy — families are not deleted via client.

-- ==========================================================================
-- 2. family_members
-- ==========================================================================
ALTER TABLE public.family_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY family_members_select ON public.family_members
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

-- Only OWNER can invite/add members.
CREATE POLICY family_members_insert ON public.family_members
  FOR INSERT WITH CHECK (
    public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

CREATE POLICY family_members_update ON public.family_members
  FOR UPDATE USING (
    public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

-- ==========================================================================
-- 3. wallets
-- ==========================================================================
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY wallets_select ON public.wallets
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

CREATE POLICY wallets_insert ON public.wallets
  FOR INSERT WITH CHECK (
    public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

CREATE POLICY wallets_update ON public.wallets
  FOR UPDATE USING (
    public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

-- ==========================================================================
-- 4. categories
-- ==========================================================================
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

-- Everyone can read system categories (family_id IS NULL) + own family categories.
CREATE POLICY categories_select ON public.categories
  FOR SELECT USING (
    family_id IS NULL
    OR family_id IN (SELECT public.get_my_family_ids())
  );

CREATE POLICY categories_insert ON public.categories
  FOR INSERT WITH CHECK (
    family_id IS NOT NULL
    AND public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

CREATE POLICY categories_update ON public.categories
  FOR UPDATE USING (
    family_id IS NOT NULL
    AND public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

-- ==========================================================================
-- 5. ledger_transactions
-- ==========================================================================
ALTER TABLE public.ledger_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY ledger_select ON public.ledger_transactions
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

-- OWNER and MEMBER can create transactions (via RPCs primarily).
-- Direct client inserts disabled to enforce atomicity through RPCs.

-- No UPDATE policy — immutability enforced by trigger in 00018.
-- No DELETE policy — deletions blocked by rule in 00018.

-- ==========================================================================
-- 6. transaction_links
-- ==========================================================================
ALTER TABLE public.transaction_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY txn_links_select ON public.transaction_links
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

-- Direct client inserts disabled to enforce atomicity through RPCs.

-- ==========================================================================
-- 7. commitments
-- ==========================================================================
ALTER TABLE public.commitments ENABLE ROW LEVEL SECURITY;

CREATE POLICY commitments_select ON public.commitments
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

CREATE POLICY commitments_insert ON public.commitments
  FOR INSERT WITH CHECK (
    public.user_has_role(family_id, ARRAY['OWNER','MEMBER']::public.member_role[])
  );

CREATE POLICY commitments_update ON public.commitments
  FOR UPDATE USING (
    public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

-- ==========================================================================
-- 8. commitment_occurrences
-- ==========================================================================
ALTER TABLE public.commitment_occurrences ENABLE ROW LEVEL SECURITY;

CREATE POLICY occurrences_select ON public.commitment_occurrences
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

CREATE POLICY occurrences_insert ON public.commitment_occurrences
  FOR INSERT WITH CHECK (
    public.user_has_role(family_id, ARRAY['OWNER','MEMBER']::public.member_role[])
  );

CREATE POLICY occurrences_update ON public.commitment_occurrences
  FOR UPDATE USING (
    public.user_has_role(family_id, ARRAY['OWNER','MEMBER']::public.member_role[])
  );

-- ==========================================================================
-- 9. sinking_funds
-- ==========================================================================
ALTER TABLE public.sinking_funds ENABLE ROW LEVEL SECURITY;

CREATE POLICY sinking_funds_select ON public.sinking_funds
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

CREATE POLICY sinking_funds_insert ON public.sinking_funds
  FOR INSERT WITH CHECK (
    public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

CREATE POLICY sinking_funds_update ON public.sinking_funds
  FOR UPDATE USING (
    public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

-- ==========================================================================
-- 10. debts
-- ==========================================================================
ALTER TABLE public.debts ENABLE ROW LEVEL SECURITY;

CREATE POLICY debts_select ON public.debts
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

CREATE POLICY debts_insert ON public.debts
  FOR INSERT WITH CHECK (
    public.user_has_role(family_id, ARRAY['OWNER','MEMBER']::public.member_role[])
  );

CREATE POLICY debts_update ON public.debts
  FOR UPDATE USING (
    public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

-- ==========================================================================
-- 11. debt_payments
-- ==========================================================================
ALTER TABLE public.debt_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY debt_payments_select ON public.debt_payments
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

-- Direct client inserts disabled to enforce atomicity through RPCs.

-- ==========================================================================
-- 12. gameya_circles
-- ==========================================================================
ALTER TABLE public.gameya_circles ENABLE ROW LEVEL SECURITY;

CREATE POLICY gameya_circles_select ON public.gameya_circles
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

CREATE POLICY gameya_circles_insert ON public.gameya_circles
  FOR INSERT WITH CHECK (
    public.user_has_role(family_id, ARRAY['OWNER','MEMBER']::public.member_role[])
  );

CREATE POLICY gameya_circles_update ON public.gameya_circles
  FOR UPDATE USING (
    public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

-- ==========================================================================
-- 13. gameya_turns
-- ==========================================================================
ALTER TABLE public.gameya_turns ENABLE ROW LEVEL SECURITY;

CREATE POLICY gameya_turns_select ON public.gameya_turns
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

CREATE POLICY gameya_turns_insert ON public.gameya_turns
  FOR INSERT WITH CHECK (
    public.user_has_role(family_id, ARRAY['OWNER','MEMBER']::public.member_role[])
  );

CREATE POLICY gameya_turns_update ON public.gameya_turns
  FOR UPDATE USING (
    public.user_has_role(family_id, ARRAY['OWNER','MEMBER']::public.member_role[])
  );

-- ==========================================================================
-- 14. budgets
-- ==========================================================================
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;

CREATE POLICY budgets_select ON public.budgets
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

CREATE POLICY budgets_insert ON public.budgets
  FOR INSERT WITH CHECK (
    public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

CREATE POLICY budgets_update ON public.budgets
  FOR UPDATE USING (
    public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );

-- ==========================================================================
-- 15. audit_events
-- ==========================================================================
ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY audit_events_select ON public.audit_events
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

-- Insert only via RPCs (SECURITY DEFINER functions handle this).
-- No direct client insert policy for audit — RPCs bypass RLS.

-- ==========================================================================
-- 16. notifications
-- ==========================================================================
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY notifications_select ON public.notifications
  FOR SELECT USING (family_id IN (SELECT public.get_my_family_ids()));

-- Members can mark their own notifications as read.
CREATE POLICY notifications_update ON public.notifications
  FOR UPDATE USING (
    recipient_member_id IN (
      SELECT id FROM public.family_members
      WHERE user_id = (SELECT auth.uid()) AND status = 'ACTIVE'
    )
  );
