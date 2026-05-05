-- =============================================================================
-- Mezan: 00030_restore_default_wallets_after_reset.sql
-- Purpose: Restore the default wallets after operational test-data reset.
--
-- This migration recreates the same baseline wallets originally created by
-- fn_create_initial_family:
-- - Cash wallet       (Arabic name: kash, REAL, sort_order 10)
-- - Bank wallet       (Arabic name: bank, REAL, sort_order 20)
-- - Emergency reserve (Arabic name: tawari, ALLOCATED, sort_order 30)
--
-- It preserves all family/member/reference data and does not create ledger
-- transactions because these wallets start at zero balance after the reset.
--
-- Idempotency:
-- Each wallet is inserted only if the family does not already have a
-- non-archived wallet with the same name and type.
-- =============================================================================

WITH primary_members AS (
  SELECT DISTINCT ON (fm.family_id)
    fm.family_id,
    fm.id AS member_id
  FROM public.family_members fm
  WHERE fm.status = 'ACTIVE'
  ORDER BY
    fm.family_id,
    CASE WHEN fm.role = 'OWNER' THEN 0 ELSE 1 END,
    fm.created_at ASC
),
default_wallets AS (
  SELECT
    fg.id AS family_id,
    pm.member_id AS created_by,
    wallet_def.name,
    wallet_def.type::public.wallet_type AS type,
    wallet_def.sort_order
  FROM public.family_groups fg
  LEFT JOIN primary_members pm ON pm.family_id = fg.id
  CROSS JOIN (
    VALUES
      (U&'\0643\0627\0634'::text, 'REAL'::text, 10),
      (U&'\0628\0646\0643'::text, 'REAL'::text, 20),
      (U&'\0637\0648\0627\0631\0626'::text, 'ALLOCATED'::text, 30)
  ) AS wallet_def(name, type, sort_order)
)
INSERT INTO public.wallets (
  family_id,
  name,
  type,
  balance,
  is_archived,
  sort_order,
  created_by
)
SELECT
  dw.family_id,
  dw.name,
  dw.type,
  0,
  false,
  dw.sort_order,
  dw.created_by
FROM default_wallets dw
WHERE NOT EXISTS (
  SELECT 1
  FROM public.wallets w
  WHERE w.family_id = dw.family_id
    AND w.name = dw.name
    AND w.type = dw.type
    AND NOT w.is_archived
);
