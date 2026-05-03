-- =============================================================================
-- Mezan: 00013_audit_and_notifications.sql
-- Audit trail for sensitive operations and user notifications.
-- =============================================================================

CREATE TABLE public.audit_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id   UUID NOT NULL
              REFERENCES public.family_groups(id) ON DELETE CASCADE,
  action      public.audit_action NOT NULL,
  actor_id    UUID REFERENCES public.family_members(id) ON DELETE SET NULL,
  target_type TEXT,  -- 'transaction', 'wallet', 'member', 'debt', 'gameya', etc.
  target_id   UUID,
  details     JSONB NOT NULL DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- User notifications (reminders, warnings, alerts).
-- ---------------------------------------------------------------------------

CREATE TABLE public.notifications (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id             UUID NOT NULL
                        REFERENCES public.family_groups(id) ON DELETE CASCADE,
  recipient_member_id   UUID REFERENCES public.family_members(id) ON DELETE CASCADE,
  title                 TEXT NOT NULL,
  body                  TEXT,
  type                  TEXT NOT NULL DEFAULT 'INFO',
  is_read               BOOLEAN NOT NULL DEFAULT false,
  reference_type        TEXT,
  reference_id          UUID,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.audit_events IS 'Immutable audit trail. Created inside atomic RPCs. Never deleted.';
COMMENT ON TABLE public.notifications IS 'User-facing alerts, reminders, and system messages.';
