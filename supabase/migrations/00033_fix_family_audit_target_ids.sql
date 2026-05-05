-- =============================================================================
-- Mezan: 00033_fix_family_audit_target_ids.sql
-- Fix target_id in audit_events and Add Direct Creation RPCs
-- =============================================================================

-- 1. Fix: fn_create_family_invitation
CREATE OR REPLACE FUNCTION public.fn_create_family_invitation(
  p_family_id UUID,
  p_email TEXT,
  p_role public.member_role,
  p_display_name TEXT,
  p_expires_at TIMESTAMPTZ
)
RETURNS UUID AS $$
DECLARE
  v_caller_member_id UUID;
  v_normalized_email TEXT;
  v_invitation_id UUID;
BEGIN
  SELECT id INTO v_caller_member_id
  FROM public.family_members
  WHERE family_id = p_family_id AND user_id = auth.uid() AND role = 'OWNER' AND status = 'ACTIVE';
    
  IF v_caller_member_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: Only active family owners can invite members.'; END IF;
  IF p_role = 'OWNER' THEN RAISE EXCEPTION 'INVALID_ROLE: Cannot invite a new OWNER in this version.'; END IF;

  v_normalized_email := lower(trim(p_email));

  INSERT INTO public.family_invitations (family_id, email, role, display_name, expires_at, invited_by)
  VALUES (p_family_id, v_normalized_email, p_role, p_display_name, p_expires_at, v_caller_member_id)
  RETURNING id INTO v_invitation_id;

  INSERT INTO public.audit_events (family_id, actor_id, action, target_type, target_id, details)
  VALUES (p_family_id, v_caller_member_id, 'MEMBER_INVITED', 'INVITATION', v_invitation_id, jsonb_build_object('email', v_normalized_email, 'role', p_role, 'display_name', p_display_name));

  RETURN v_invitation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_create_family_invitation(UUID, TEXT, public.member_role, TEXT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_family_invitation(UUID, TEXT, public.member_role, TEXT, TIMESTAMPTZ) TO authenticated;


-- 2. Fix: fn_revoke_family_invitation
CREATE OR REPLACE FUNCTION public.fn_revoke_family_invitation(
  p_family_id UUID,
  p_invitation_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_caller_member_id UUID;
  v_invitation public.family_invitations%ROWTYPE;
BEGIN
  SELECT id INTO v_caller_member_id
  FROM public.family_members
  WHERE family_id = p_family_id AND user_id = auth.uid() AND role = 'OWNER' AND status = 'ACTIVE';
    
  IF v_caller_member_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: Only active family owners can revoke invitations.'; END IF;

  SELECT * INTO v_invitation FROM public.family_invitations WHERE id = p_invitation_id AND family_id = p_family_id FOR UPDATE;
  IF v_invitation IS NULL THEN RAISE EXCEPTION 'NOT_FOUND: Invitation not found.'; END IF;
  IF v_invitation.status != 'PENDING' THEN RAISE EXCEPTION 'INVALID_STATUS: Invitation is already %', v_invitation.status; END IF;

  UPDATE public.family_invitations SET status = 'REVOKED' WHERE id = p_invitation_id;

  INSERT INTO public.audit_events (family_id, actor_id, action, target_type, target_id, details)
  VALUES (p_family_id, v_caller_member_id, 'SETTINGS_CHANGED', 'INVITATION_REVOKED', p_invitation_id, jsonb_build_object('email', v_invitation.email));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_revoke_family_invitation(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_revoke_family_invitation(UUID, UUID) TO authenticated;


-- 3. Fix: fn_change_family_member_role
CREATE OR REPLACE FUNCTION public.fn_change_family_member_role(
  p_family_id UUID,
  p_member_id UUID,
  p_new_role public.member_role
)
RETURNS VOID AS $$
DECLARE
  v_caller_member_id UUID;
  v_target_member public.family_members%ROWTYPE;
BEGIN
  SELECT id INTO v_caller_member_id
  FROM public.family_members
  WHERE family_id = p_family_id AND user_id = auth.uid() AND role = 'OWNER' AND status = 'ACTIVE';
    
  IF v_caller_member_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: Only active family owners can change roles.'; END IF;

  SELECT * INTO v_target_member FROM public.family_members WHERE id = p_member_id AND family_id = p_family_id FOR UPDATE;
  IF v_target_member IS NULL THEN RAISE EXCEPTION 'NOT_FOUND: Member not found in family.'; END IF;

  UPDATE public.family_members SET role = p_new_role WHERE id = p_member_id;

  INSERT INTO public.audit_events (family_id, actor_id, action, target_type, target_id, details)
  VALUES (p_family_id, v_caller_member_id, 'MEMBER_ROLE_CHANGED', 'MEMBER', p_member_id, jsonb_build_object('old_role', v_target_member.role, 'new_role', p_new_role));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_change_family_member_role(UUID, UUID, public.member_role) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_change_family_member_role(UUID, UUID, public.member_role) TO authenticated;


-- 4. Fix: fn_suspend_family_member
CREATE OR REPLACE FUNCTION public.fn_suspend_family_member(
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
    
  IF v_caller_member_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: Only active family owners can suspend members.'; END IF;

  SELECT * INTO v_target_member FROM public.family_members WHERE id = p_member_id AND family_id = p_family_id FOR UPDATE;
  IF v_target_member IS NULL THEN RAISE EXCEPTION 'NOT_FOUND: Member not found in family.'; END IF;
  IF v_target_member.user_id = auth.uid() THEN RAISE EXCEPTION 'INVALID_ACTION: Cannot suspend yourself.'; END IF;

  UPDATE public.family_members SET status = 'SUSPENDED' WHERE id = p_member_id;

  INSERT INTO public.audit_events (family_id, actor_id, action, target_type, target_id, details)
  VALUES (p_family_id, v_caller_member_id, 'SETTINGS_CHANGED', 'MEMBER_SUSPENDED', p_member_id, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_suspend_family_member(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_suspend_family_member(UUID, UUID) TO authenticated;


-- 5. Fix: fn_reactivate_family_member
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

  UPDATE public.family_members SET status = 'ACTIVE' WHERE id = p_member_id;

  INSERT INTO public.audit_events (family_id, actor_id, action, target_type, target_id, details)
  VALUES (p_family_id, v_caller_member_id, 'SETTINGS_CHANGED', 'MEMBER_REACTIVATED', p_member_id, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_reactivate_family_member(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reactivate_family_member(UUID, UUID) TO authenticated;


-- =============================================================================
-- Direct Member Creation Support
-- =============================================================================

-- 6. Helper: fn_assert_can_direct_create_family_member
-- Only OWNERs can direct-create members, and they cannot create new OWNERs.
CREATE OR REPLACE FUNCTION public.fn_assert_can_direct_create_family_member(
  p_family_id UUID,
  p_role public.member_role
)
RETURNS VOID AS $$
DECLARE
  v_caller_member_id UUID;
BEGIN
  SELECT id INTO v_caller_member_id
  FROM public.family_members
  WHERE family_id = p_family_id AND user_id = auth.uid() AND role = 'OWNER' AND status = 'ACTIVE';
    
  IF v_caller_member_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: Only active family owners can direct-create members.'; END IF;
  IF p_role = 'OWNER' THEN RAISE EXCEPTION 'INVALID_ROLE: Cannot create a new OWNER directly.'; END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_assert_can_direct_create_family_member(UUID, public.member_role) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_assert_can_direct_create_family_member(UUID, public.member_role) TO authenticated;


-- 7. Add Existing User To Family (Direct Creation Link)
CREATE OR REPLACE FUNCTION public.fn_add_existing_user_to_family(
  p_family_id UUID,
  p_user_id UUID,
  p_role public.member_role,
  p_display_name TEXT
)
RETURNS UUID AS $$
DECLARE
  v_caller_member_id UUID;
  v_existing_active_family UUID;
  v_new_member_id UUID;
BEGIN
  -- 1. Assert Caller permissions
  SELECT id INTO v_caller_member_id
  FROM public.family_members
  WHERE family_id = p_family_id AND user_id = auth.uid() AND role = 'OWNER' AND status = 'ACTIVE';
    
  IF v_caller_member_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: Only active family owners can direct-create members.'; END IF;
  IF p_role = 'OWNER' THEN RAISE EXCEPTION 'INVALID_ROLE: Cannot create a new OWNER directly.'; END IF;

  -- 2. Enforce MVP Rule: One active family per user
  SELECT family_id INTO v_existing_active_family
  FROM public.family_members
  WHERE user_id = p_user_id AND status = 'ACTIVE'
  LIMIT 1;

  IF v_existing_active_family IS NOT NULL THEN
    RAISE EXCEPTION 'ONE_FAMILY_LIMIT: User is already an active member of a family.';
  END IF;

  -- 3. Upsert into family_members
  INSERT INTO public.family_members (family_id, user_id, role, status, display_name)
  VALUES (p_family_id, p_user_id, p_role, 'ACTIVE', p_display_name)
  ON CONFLICT (family_id, user_id) 
  DO UPDATE SET status = 'ACTIVE', role = EXCLUDED.role, display_name = COALESCE(EXCLUDED.display_name, public.family_members.display_name)
  RETURNING id INTO v_new_member_id;

  -- 4. Audit Trail
  INSERT INTO public.audit_events (family_id, actor_id, action, target_type, target_id, details)
  VALUES (
    p_family_id, 
    v_caller_member_id, 
    'SETTINGS_CHANGED', 
    'MEMBER', 
    v_new_member_id, 
    jsonb_build_object('event', 'MEMBER_CREATED_DIRECTLY', 'role', p_role, 'display_name', p_display_name)
  );

  RETURN v_new_member_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_add_existing_user_to_family(UUID, UUID, public.member_role, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_add_existing_user_to_family(UUID, UUID, public.member_role, TEXT) TO authenticated;
