-- =============================================================================
-- Mezan: 00003_family_members.sql
-- Links auth.users to family_groups with role-based permissions.
-- This table is the foundation of every RLS policy in the system.
-- =============================================================================

CREATE TABLE public.family_members (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id     UUID NOT NULL
                REFERENCES public.family_groups(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL
                REFERENCES auth.users(id) ON DELETE CASCADE,
  role          public.member_role NOT NULL DEFAULT 'MEMBER',
  status        public.member_status NOT NULL DEFAULT 'ACTIVE',
  display_name  TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT uq_family_user UNIQUE (family_id, user_id)
);

CREATE TRIGGER trg_family_members_updated_at
  BEFORE UPDATE ON public.family_members
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.family_members IS 'Join table: auth.users ↔ family_groups. Basis for all RLS.';
COMMENT ON COLUMN public.family_members.role IS 'OWNER manages everything; MEMBER records transactions; VIEWER is read-only.';
