-- Migration 00034: Category Governance RPCs

BEGIN;

-- 1. Remove direct INSERT/UPDATE/DELETE policies on categories
DROP POLICY IF EXISTS "categories_insert" ON public.categories;
DROP POLICY IF EXISTS "categories_update" ON public.categories;
-- Keep "Enable read access for all users" or similar SELECT policy

-- Helper function to get member_id and check role
CREATE OR REPLACE FUNCTION public._require_category_owner(p_family_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_member_id UUID;
  v_role public.member_role;
  v_status public.member_status;
BEGIN
  SELECT id, role, status INTO v_member_id, v_role, v_status
  FROM public.family_members
  WHERE family_id = p_family_id
    AND user_id = auth.uid()
    AND status = 'ACTIVE';

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: You are not an active member of this family.';
  END IF;

  IF v_role != 'OWNER' THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only OWNER can manage categories.';
  END IF;

  RETURN v_member_id;
END;
$$;

-- 2. Create Category RPC
CREATE OR REPLACE FUNCTION public.fn_create_family_category(
  p_family_id UUID,
  p_name_ar TEXT,
  p_name_en TEXT DEFAULT NULL,
  p_direction public.category_direction DEFAULT 'EXPENSE',
  p_behavior public.category_behavior DEFAULT 'VARIABLE_BUDGETED',
  p_parent_id UUID DEFAULT NULL,
  p_priority_level INTEGER DEFAULT 0,
  p_icon TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor_id UUID;
  v_new_category_id UUID;
  v_parent_family_id UUID;
  v_parent_direction public.category_direction;
  v_parent_is_archived BOOLEAN;
BEGIN
  v_actor_id := public._require_category_owner(p_family_id);

  IF p_behavior = 'SYSTEM' THEN
    RAISE EXCEPTION 'INVALID_ACTION: Cannot create custom categories with SYSTEM behavior.';
  END IF;

  IF p_parent_id IS NOT NULL THEN
    SELECT family_id, direction, is_archived 
    INTO v_parent_family_id, v_parent_direction, v_parent_is_archived
    FROM public.categories WHERE id = p_parent_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'INVALID_PARENT: Parent category does not exist.';
    END IF;

    IF v_parent_is_archived THEN
      RAISE EXCEPTION 'INVALID_PARENT: Cannot nest under an archived category.';
    END IF;

    IF v_parent_direction != p_direction THEN
      RAISE EXCEPTION 'INVALID_DIRECTION: Parent category direction must match.';
    END IF;

    IF v_parent_family_id IS NOT NULL AND v_parent_family_id != p_family_id THEN
      RAISE EXCEPTION 'INVALID_PARENT: Parent category belongs to another family.';
    END IF;
  END IF;

  INSERT INTO public.categories (
    family_id, name_ar, name_en, direction, behavior, parent_id, priority_level, icon, is_system, is_archived
  ) VALUES (
    p_family_id, p_name_ar, p_name_en, p_direction, p_behavior, p_parent_id, p_priority_level, p_icon, false, false
  ) RETURNING id INTO v_new_category_id;

  INSERT INTO public.audit_events (family_id, actor_id, action, target_id, target_type, details)
  VALUES (p_family_id, v_actor_id, 'SETTINGS_CHANGED', v_new_category_id, 'CATEGORY', 
    jsonb_build_object('action', 'CREATE', 'name_ar', p_name_ar, 'direction', p_direction));

  RETURN v_new_category_id;
END;
$$;

-- 3. Update Category RPC
CREATE OR REPLACE FUNCTION public.fn_update_family_category(
  p_family_id UUID,
  p_category_id UUID,
  p_name_ar TEXT,
  p_name_en TEXT DEFAULT NULL,
  p_behavior public.category_behavior DEFAULT 'VARIABLE_BUDGETED',
  p_parent_id UUID DEFAULT NULL,
  p_priority_level INTEGER DEFAULT 0,
  p_icon TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor_id UUID;
  v_cat_family_id UUID;
  v_cat_direction public.category_direction;
  v_parent_family_id UUID;
  v_parent_direction public.category_direction;
  v_parent_is_archived BOOLEAN;
BEGIN
  v_actor_id := public._require_category_owner(p_family_id);

  IF p_behavior = 'SYSTEM' THEN
    RAISE EXCEPTION 'INVALID_ACTION: Cannot set custom category behavior to SYSTEM.';
  END IF;

  SELECT family_id, direction INTO v_cat_family_id, v_cat_direction
  FROM public.categories WHERE id = p_category_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Category does not exist.';
  END IF;

  IF v_cat_family_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_ACTION: Cannot modify system categories.';
  END IF;

  IF v_cat_family_id != p_family_id THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Category belongs to another family.';
  END IF;

  IF p_parent_id IS NOT NULL THEN
    IF p_parent_id = p_category_id THEN
      RAISE EXCEPTION 'INVALID_PARENT: Category cannot be its own parent.';
    END IF;

    SELECT family_id, direction, is_archived 
    INTO v_parent_family_id, v_parent_direction, v_parent_is_archived
    FROM public.categories WHERE id = p_parent_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'INVALID_PARENT: Parent category does not exist.';
    END IF;

    IF v_parent_is_archived THEN
      RAISE EXCEPTION 'INVALID_PARENT: Cannot nest under an archived category.';
    END IF;

    IF v_parent_direction != v_cat_direction THEN
      RAISE EXCEPTION 'INVALID_DIRECTION: Parent category direction must match.';
    END IF;

    IF v_parent_family_id IS NOT NULL AND v_parent_family_id != p_family_id THEN
      RAISE EXCEPTION 'INVALID_PARENT: Parent category belongs to another family.';
    END IF;
  END IF;

  UPDATE public.categories SET
    name_ar = p_name_ar,
    name_en = p_name_en,
    behavior = p_behavior,
    parent_id = p_parent_id,
    priority_level = p_priority_level,
    icon = p_icon
  WHERE id = p_category_id;

  INSERT INTO public.audit_events (family_id, actor_id, action, target_id, target_type, details)
  VALUES (p_family_id, v_actor_id, 'SETTINGS_CHANGED', p_category_id, 'CATEGORY', 
    jsonb_build_object('action', 'UPDATE', 'name_ar', p_name_ar));

END;
$$;

-- 4. Archive Category RPC
CREATE OR REPLACE FUNCTION public.fn_archive_family_category(
  p_family_id UUID,
  p_category_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor_id UUID;
  v_cat_family_id UUID;
  v_cat_name_ar TEXT;
BEGIN
  v_actor_id := public._require_category_owner(p_family_id);

  SELECT family_id, name_ar INTO v_cat_family_id, v_cat_name_ar
  FROM public.categories WHERE id = p_category_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Category does not exist.';
  END IF;

  IF v_cat_family_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_ACTION: Cannot archive system categories.';
  END IF;

  IF v_cat_family_id != p_family_id THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Category belongs to another family.';
  END IF;

  -- Check for active children
  IF EXISTS (
    SELECT 1 FROM public.categories 
    WHERE parent_id = p_category_id AND is_archived = false
  ) THEN
    RAISE EXCEPTION 'HAS_ACTIVE_CHILDREN: Cannot archive category with active sub-categories.';
  END IF;

  -- Check for active budgets
  IF EXISTS (
    SELECT 1 FROM public.budgets
    WHERE category_id = p_category_id
      AND cycle_end >= CURRENT_DATE
  ) THEN
    RAISE EXCEPTION 'HAS_ACTIVE_BUDGET: Cannot archive category linked to an active budget.';
  END IF;

  -- Check for active commitments
  IF EXISTS (
    SELECT 1 FROM public.commitments
    WHERE category_id = p_category_id
      AND is_active = true
  ) THEN
    RAISE EXCEPTION 'HAS_ACTIVE_COMMITMENT: Cannot archive category linked to an active commitment.';
  END IF;

  UPDATE public.categories SET is_archived = true WHERE id = p_category_id;

  INSERT INTO public.audit_events (family_id, actor_id, action, target_id, target_type, details)
  VALUES (p_family_id, v_actor_id, 'SETTINGS_CHANGED', p_category_id, 'CATEGORY', 
    jsonb_build_object('action', 'ARCHIVE', 'name_ar', v_cat_name_ar));

END;
$$;

-- Secure the functions
REVOKE ALL ON FUNCTION public._require_category_owner(UUID) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.fn_create_family_category(UUID, TEXT, TEXT, public.category_direction, public.category_behavior, UUID, INTEGER, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_update_family_category(UUID, UUID, TEXT, TEXT, public.category_behavior, UUID, INTEGER, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_archive_family_category(UUID, UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_create_family_category(UUID, TEXT, TEXT, public.category_direction, public.category_behavior, UUID, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_update_family_category(UUID, UUID, TEXT, TEXT, public.category_behavior, UUID, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_archive_family_category(UUID, UUID) TO authenticated;

COMMIT;
