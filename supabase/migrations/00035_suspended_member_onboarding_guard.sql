-- =============================================================================
-- Mezan: 00035_suspended_member_onboarding_guard.sql
-- Fix the logical loophole where a suspended user creates a new family.
-- =============================================================================

BEGIN;

-- 1. Create fn_get_my_membership_state
-- Helper RPC/View to safely get the current membership state bypassing RLS.
CREATE OR REPLACE FUNCTION public.fn_get_my_membership_state()
RETURNS TABLE(
  family_id UUID, 
  member_id UUID, 
  role public.member_role, 
  status TEXT, 
  family_name TEXT,
  blocking_reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_active_count INT;
  v_suspended_count INT;
  v_invited_count INT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, NULL::UUID, NULL::public.member_role, 'NO_MEMBERSHIP'::TEXT, NULL::TEXT, NULL::TEXT;
    RETURN;
  END IF;

  SELECT 
    COUNT(*) FILTER (WHERE fm.status = 'ACTIVE'),
    COUNT(*) FILTER (WHERE fm.status = 'SUSPENDED'),
    COUNT(*) FILTER (WHERE fm.status = 'INVITED')
  INTO v_active_count, v_suspended_count, v_invited_count
  FROM public.family_members fm
  WHERE fm.user_id = v_uid;

  -- Condition: Conflict
  IF v_active_count > 1 OR (v_active_count > 0 AND v_suspended_count > 0) THEN
    RETURN QUERY SELECT NULL::UUID, NULL::UUID, NULL::public.member_role, 'CONFLICT'::TEXT, NULL::TEXT, 'MEMBERSHIP_CONFLICT'::TEXT;
    RETURN;
  END IF;

  -- Condition: Active
  IF v_active_count = 1 THEN
    RETURN QUERY 
      SELECT fm.family_id, fm.id, fm.role, 'ACTIVE'::TEXT, fg.name, NULL::TEXT
      FROM public.family_members fm
      JOIN public.family_groups fg ON fm.family_id = fg.id
      WHERE fm.user_id = v_uid AND fm.status = 'ACTIVE' LIMIT 1;
    RETURN;
  END IF;

  -- Condition: Suspended
  IF v_suspended_count > 0 THEN
    RETURN QUERY 
      SELECT fm.family_id, fm.id, fm.role, 'SUSPENDED'::TEXT, fg.name, NULL::TEXT
      FROM public.family_members fm
      JOIN public.family_groups fg ON fm.family_id = fg.id
      WHERE fm.user_id = v_uid AND fm.status = 'SUSPENDED' LIMIT 1;
    RETURN;
  END IF;

  -- Condition: Invited
  IF v_invited_count > 0 THEN
    RETURN QUERY 
      SELECT fm.family_id, fm.id, fm.role, 'INVITED'::TEXT, fg.name, NULL::TEXT
      FROM public.family_members fm
      JOIN public.family_groups fg ON fm.family_id = fg.id
      WHERE fm.user_id = v_uid AND fm.status = 'INVITED' LIMIT 1;
    RETURN;
  END IF;

  -- Default: No Membership
  RETURN QUERY SELECT NULL::UUID, NULL::UUID, NULL::public.member_role, 'NO_MEMBERSHIP'::TEXT, NULL::TEXT, NULL::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_get_my_membership_state() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_get_my_membership_state() TO authenticated;


-- 2. Update fn_create_initial_family to use state guard
CREATE OR REPLACE FUNCTION public.fn_create_initial_family(
  p_family_name text default null,
  p_display_name text default null
)
RETURNS TABLE (family_id UUID, member_id UUID) 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_fam_id UUID;
  v_mem_id UUID;
  v_family_name text := COALESCE(p_family_name, 'عائلتي');
  v_state_status TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED';
  END IF;

  -- Lock the user row to serialize concurrent onboarding attempts
  PERFORM 1 FROM auth.users WHERE id = v_uid FOR UPDATE;

  -- Check user membership status
  SELECT status INTO v_state_status FROM public.fn_get_my_membership_state();

  IF v_state_status = 'ACTIVE' THEN
    RAISE EXCEPTION 'ALREADY_HAS_ACTIVE_FAMILY';
  ELSIF v_state_status = 'SUSPENDED' THEN
    RAISE EXCEPTION 'MEMBERSHIP_SUSPENDED';
  ELSIF v_state_status = 'INVITED' THEN
    RAISE EXCEPTION 'MEMBERSHIP_PENDING';
  ELSIF v_state_status = 'CONFLICT' THEN
    RAISE EXCEPTION 'MEMBERSHIP_CONFLICT';
  END IF;

  -- Only NO_MEMBERSHIP can proceed

  -- Create family
  INSERT INTO public.family_groups(name) 
  VALUES (v_family_name) 
  RETURNING id INTO v_fam_id;

  -- Create membership
  INSERT INTO public.family_members(family_id, user_id, role, status, display_name)
  VALUES (v_fam_id, v_uid, 'OWNER', 'ACTIVE', p_display_name) 
  RETURNING id INTO v_mem_id;

  -- Create default wallets
  INSERT INTO public.wallets(family_id, name, type, sort_order, created_by) VALUES 
    (v_fam_id, 'كاش', 'REAL', 10, v_mem_id),
    (v_fam_id, 'بنك', 'REAL', 20, v_mem_id),
    (v_fam_id, 'طوارئ', 'ALLOCATED', 30, v_mem_id);

  -- Create audit event
  INSERT INTO public.audit_events(family_id, action, actor_id, target_type, target_id, details)
  VALUES (
    v_fam_id, 
    'MEMBER_INVITED', 
    v_mem_id, 
    'member', 
    v_mem_id, 
    jsonb_build_object('role', 'OWNER', 'note', 'Initial family creation via onboarding')
  );

  RETURN QUERY SELECT v_fam_id, v_mem_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_create_initial_family(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_initial_family(text, text) TO authenticated;


-- 3. Update fn_reactivate_family_member to catch conflicts before unique index
CREATE OR REPLACE FUNCTION public.fn_reactivate_family_member(
  p_family_id UUID,
  p_member_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_caller_member_id UUID;
  v_target_member public.family_members%ROWTYPE;
BEGIN
  SELECT id INTO v_caller_member_id
  FROM public.family_members
  WHERE family_id = p_family_id AND user_id = auth.uid() AND role = 'OWNER' AND status = 'ACTIVE';
    
  IF v_caller_member_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: Only active family owners can reactivate members.'; END IF;

  SELECT * INTO v_target_member FROM public.family_members WHERE id = p_member_id AND family_id = p_family_id FOR UPDATE;
  IF v_target_member IS NULL THEN RAISE EXCEPTION 'NOT_FOUND: Member not found in family.'; END IF;

  -- GUARD: Check if the user already has another ACTIVE family
  IF EXISTS (
    SELECT 1 FROM public.family_members 
    WHERE user_id = v_target_member.user_id AND status = 'ACTIVE'
  ) THEN
    RAISE EXCEPTION 'ONE_FAMILY_LIMIT: User already has an active family membership.';
  END IF;

  UPDATE public.family_members SET status = 'ACTIVE' WHERE id = p_member_id;

  INSERT INTO public.audit_events (family_id, actor_id, action, target_type, target_id, details)
  VALUES (p_family_id, v_caller_member_id, 'SETTINGS_CHANGED', 'MEMBER_REACTIVATED', p_member_id, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_reactivate_family_member(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reactivate_family_member(UUID, UUID) TO authenticated;

COMMIT;

-- =============================================================================
-- DIAGNOSTIC REPORT (DO NOT UNCOMMENT/EXECUTE IN MIGRATION)
-- =============================================================================
/*
-- Find users with conflicting memberships (e.g. SUSPENDED in one, ACTIVE in another)
SELECT m1.user_id, 
       m1.family_id as suspended_family_id, 
       m2.family_id as active_family_id
FROM public.family_members m1
JOIN public.family_members m2 ON m1.user_id = m2.user_id
WHERE m1.status = 'SUSPENDED' AND m2.status = 'ACTIVE';
*/
