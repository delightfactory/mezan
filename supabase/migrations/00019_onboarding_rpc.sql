-- =============================================================================
-- Mezan: 00019_onboarding_rpc.sql
-- Secure RPC for onboarding the first family and avoiding orphan records.
-- =============================================================================

-- Enforce maximum of one ACTIVE family membership per user
CREATE UNIQUE INDEX IF NOT EXISTS uq_family_members_one_active_family_per_user
ON public.family_members(user_id)
WHERE status = 'ACTIVE';

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
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED';
  END IF;

  -- Lock the user row to serialize concurrent onboarding attempts
  PERFORM 1 FROM auth.users WHERE id = v_uid FOR UPDATE;

  -- Check if user already has an active family membership
  IF EXISTS (
    SELECT 1 FROM public.family_members 
    WHERE user_id = v_uid AND status = 'ACTIVE'
  ) THEN
    RAISE EXCEPTION 'ALREADY_HAS_ACTIVE_FAMILY';
  END IF;

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
REVOKE ALL ON FUNCTION public.fn_create_initial_family(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_create_initial_family(text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- RLS Hardening (Incremental safety overriding 00014)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS family_groups_insert ON public.family_groups;
DROP POLICY IF EXISTS family_members_insert ON public.family_members;

CREATE POLICY family_members_insert ON public.family_members
  FOR INSERT WITH CHECK (
    public.user_has_role(family_id, ARRAY['OWNER']::public.member_role[])
  );
