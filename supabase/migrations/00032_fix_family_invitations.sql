-- =============================================================================
-- Mezan: 00032_fix_family_invitations.sql
-- Fix Family Administration RPCs
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
  -- Verify caller is active OWNER
  SELECT id INTO v_caller_member_id
  FROM public.family_members
  WHERE family_id = p_family_id
    AND user_id = auth.uid()
    AND role = 'OWNER'
    AND status = 'ACTIVE';
    
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only active family owners can invite members.';
  END IF;

  -- Enforce MVP role limits: Do not allow inviting new OWNERs
  IF p_role = 'OWNER' THEN
    RAISE EXCEPTION 'INVALID_ROLE: Cannot invite a new OWNER in this version.';
  END IF;

  v_normalized_email := lower(trim(p_email));

  -- Insert (conflict on unique partial index handled by DB)
  INSERT INTO public.family_invitations (family_id, email, role, display_name, expires_at, invited_by)
  VALUES (p_family_id, v_normalized_email, p_role, p_display_name, p_expires_at, v_caller_member_id)
  RETURNING id INTO v_invitation_id;

  -- Audit: Use v_caller_member_id as actor_id
  INSERT INTO public.audit_events (family_id, actor_id, action, target_type, target_id, details)
  VALUES (
    p_family_id,
    v_caller_member_id,
    'MEMBER_INVITED',
    'INVITATION',
    v_invitation_id,
    jsonb_build_object('email', v_normalized_email, 'role', p_role, 'display_name', p_display_name)
  );

  RETURN v_invitation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_create_family_invitation(UUID, TEXT, public.member_role, TEXT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_family_invitation(UUID, TEXT, public.member_role, TEXT, TIMESTAMPTZ) TO authenticated;


-- 2. Fix: fn_accept_family_invitation
CREATE OR REPLACE FUNCTION public.fn_accept_family_invitation(
  p_invitation_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_invitation public.family_invitations%ROWTYPE;
  v_caller_email TEXT;
  v_existing_active_family UUID;
BEGIN
  -- Get invitation
  SELECT * INTO v_invitation
  FROM public.family_invitations
  WHERE id = p_invitation_id FOR UPDATE;

  IF v_invitation IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: Invitation not found.';
  END IF;

  IF v_invitation.status != 'PENDING' THEN
    RAISE EXCEPTION 'INVALID_STATUS: Invitation is already %', v_invitation.status;
  END IF;

  IF v_invitation.expires_at < now() THEN
    UPDATE public.family_invitations SET status = 'EXPIRED' WHERE id = p_invitation_id;
    RAISE EXCEPTION 'EXPIRED: Invitation has expired.';
  END IF;

  -- Get caller email from JWT
  v_caller_email := lower(trim(auth.jwt() ->> 'email'));
  IF v_caller_email IS NULL THEN
    -- Fallback for testing/certain auth flows
    SELECT lower(trim(email)) INTO v_caller_email FROM auth.users WHERE id = auth.uid();
  END IF;

  IF v_caller_email != v_invitation.email THEN
    RAISE EXCEPTION 'EMAIL_MISMATCH: Your authenticated email does not match the invitation email.';
  END IF;

  -- Check uq_family_members_one_active_family_per_user (MVP restriction)
  SELECT family_id INTO v_existing_active_family
  FROM public.family_members
  WHERE user_id = auth.uid() AND status = 'ACTIVE'
  LIMIT 1;

  IF v_existing_active_family IS NOT NULL THEN
    RAISE EXCEPTION 'ONE_FAMILY_LIMIT: You are already an active member of another family.';
  END IF;

  -- Mark accepted
  UPDATE public.family_invitations
  SET status = 'ACCEPTED', accepted_by_user_id = auth.uid(), accepted_at = now()
  WHERE id = p_invitation_id;

  -- Create or Update Family Member record
  INSERT INTO public.family_members (family_id, user_id, role, status, display_name)
  VALUES (v_invitation.family_id, auth.uid(), v_invitation.role, 'ACTIVE', v_invitation.display_name)
  ON CONFLICT (family_id, user_id) 
  DO UPDATE SET status = 'ACTIVE', role = v_invitation.role, display_name = COALESCE(EXCLUDED.display_name, public.family_members.display_name);

END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_accept_family_invitation(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_accept_family_invitation(UUID) TO authenticated;


-- 3. Fix: fn_revoke_family_invitation
CREATE OR REPLACE FUNCTION public.fn_revoke_family_invitation(
  p_family_id UUID,
  p_invitation_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_caller_member_id UUID;
  v_invitation public.family_invitations%ROWTYPE;
BEGIN
  -- Verify caller is active OWNER
  SELECT id INTO v_caller_member_id
  FROM public.family_members
  WHERE family_id = p_family_id
    AND user_id = auth.uid()
    AND role = 'OWNER'
    AND status = 'ACTIVE';
    
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only active family owners can revoke invitations.';
  END IF;

  SELECT * INTO v_invitation
  FROM public.family_invitations
  WHERE id = p_invitation_id AND family_id = p_family_id FOR UPDATE;

  IF v_invitation IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: Invitation not found.';
  END IF;

  IF v_invitation.status != 'PENDING' THEN
    RAISE EXCEPTION 'INVALID_STATUS: Invitation is already %', v_invitation.status;
  END IF;

  UPDATE public.family_invitations SET status = 'REVOKED' WHERE id = p_invitation_id;

  -- Audit
  INSERT INTO public.audit_events (family_id, actor_id, action, target_type, target_id, details)
  VALUES (
    p_family_id,
    v_caller_member_id,
    'SETTINGS_CHANGED',
    'INVITATION_REVOKED',
    p_invitation_id,
    jsonb_build_object('email', v_invitation.email)
  );

END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_revoke_family_invitation(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_revoke_family_invitation(UUID, UUID) TO authenticated;


-- 4. Fix: fn_change_family_member_role
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
  -- Verify caller is active OWNER
  SELECT id INTO v_caller_member_id
  FROM public.family_members
  WHERE family_id = p_family_id
    AND user_id = auth.uid()
    AND role = 'OWNER'
    AND status = 'ACTIVE';
    
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only active family owners can change roles.';
  END IF;

  SELECT * INTO v_target_member
  FROM public.family_members
  WHERE id = p_member_id AND family_id = p_family_id FOR UPDATE;

  IF v_target_member IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: Member not found in family.';
  END IF;

  -- Update trigger on family_members already prevents removing/demoting the last active OWNER
  UPDATE public.family_members SET role = p_new_role WHERE id = p_member_id;

  -- Audit
  INSERT INTO public.audit_events (family_id, actor_id, action, target_type, target_id, details)
  VALUES (
    p_family_id,
    v_caller_member_id,
    'MEMBER_ROLE_CHANGED',
    'MEMBER',
    p_member_id,
    jsonb_build_object('old_role', v_target_member.role, 'new_role', p_new_role)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_change_family_member_role(UUID, UUID, public.member_role) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_change_family_member_role(UUID, UUID, public.member_role) TO authenticated;


-- 5. Fix: fn_suspend_family_member
CREATE OR REPLACE FUNCTION public.fn_suspend_family_member(
  p_family_id UUID,
  p_member_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_caller_member_id UUID;
  v_target_member public.family_members%ROWTYPE;
BEGIN
  -- Verify caller is active OWNER
  SELECT id INTO v_caller_member_id
  FROM public.family_members
  WHERE family_id = p_family_id
    AND user_id = auth.uid()
    AND role = 'OWNER'
    AND status = 'ACTIVE';
    
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only active family owners can suspend members.';
  END IF;

  SELECT * INTO v_target_member
  FROM public.family_members
  WHERE id = p_member_id AND family_id = p_family_id FOR UPDATE;

  IF v_target_member IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: Member not found in family.';
  END IF;

  -- Cannot suspend self 
  IF v_target_member.user_id = auth.uid() THEN
    RAISE EXCEPTION 'INVALID_ACTION: Cannot suspend yourself.';
  END IF;

  -- Update trigger protects last OWNER
  UPDATE public.family_members SET status = 'SUSPENDED' WHERE id = p_member_id;

  -- Audit
  INSERT INTO public.audit_events (family_id, actor_id, action, target_type, target_id, details)
  VALUES (
    p_family_id,
    v_caller_member_id,
    'SETTINGS_CHANGED',
    'MEMBER_SUSPENDED',
    p_member_id,
    '{}'::jsonb
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_suspend_family_member(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_suspend_family_member(UUID, UUID) TO authenticated;


-- 6. Fix: fn_reactivate_family_member
CREATE OR REPLACE FUNCTION public.fn_reactivate_family_member(
  p_family_id UUID,
  p_member_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_caller_member_id UUID;
  v_target_member public.family_members%ROWTYPE;
BEGIN
  -- Verify caller is active OWNER
  SELECT id INTO v_caller_member_id
  FROM public.family_members
  WHERE family_id = p_family_id
    AND user_id = auth.uid()
    AND role = 'OWNER'
    AND status = 'ACTIVE';
    
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only active family owners can reactivate members.';
  END IF;

  SELECT * INTO v_target_member
  FROM public.family_members
  WHERE id = p_member_id AND family_id = p_family_id FOR UPDATE;

  IF v_target_member IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND: Member not found in family.';
  END IF;

  UPDATE public.family_members SET status = 'ACTIVE' WHERE id = p_member_id;

  -- Audit
  INSERT INTO public.audit_events (family_id, actor_id, action, target_type, target_id, details)
  VALUES (
    p_family_id,
    v_caller_member_id,
    'SETTINGS_CHANGED',
    'MEMBER_REACTIVATED',
    p_member_id,
    '{}'::jsonb
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.fn_reactivate_family_member(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reactivate_family_member(UUID, UUID) TO authenticated;
