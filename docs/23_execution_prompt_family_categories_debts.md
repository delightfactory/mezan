# Execution Prompt: Family Admin, Categories Governance, And Debt Expansion

Use this prompt with the implementation agent/tool that will modify the codebase.

---

You are working on Mezan, a Supabase + React/TypeScript family-finance control system for Egyptian households. Treat it as a financial-control system, not a simple expense tracker.

## Read First

Before writing code, read these files:

- `.codex/skills/mezan-development-governance/SKILL.md`
- `.codex/skills/mezan-development-governance/references/research-gates.md`
- `.codex/skills/mezan-development-governance/references/domain-rules.md`
- `docs/00_product_and_domain_blueprint.md`
- `docs/03_development_roadmap_and_gates.md`
- `docs/04_mvp_scope_and_scenario_matrix.md`
- `docs/22_family_auth_permissions_plan.md`
- `supabase/migrations/00001_enums_and_domains.sql`
- `supabase/migrations/00003_family_members.sql`
- `supabase/migrations/00005_categories.sql`
- `supabase/migrations/00010_debts.sql`
- `supabase/migrations/00014_rls_policies.sql`
- `supabase/migrations/00016_financial_functions.sql`
- `supabase/migrations/00018_immutability_guards.sql`
- `src/App.tsx`
- `src/services/categoryService.ts`
- `src/services/debtService.ts`
- `src/types/rpc/contracts.ts`
- `src/types/schemas/index.ts`

## Current System Snapshot

- Database migrations already cover families, members, wallets, categories, immutable ledger, commitments, debts, gameya, budgets, audit, notifications, RLS, and many atomic RPCs.
- `member_role` currently has `OWNER`, `MEMBER`, `VIEWER`.
- `member_status` currently has `ACTIVE`, `INVITED`, `SUSPENDED`.
- There is no `supabase/functions` directory yet. Edge Functions must be added from scratch.
- Family/member management UI is currently missing from `src/App.tsx`.
- Category service currently reads system/family categories and directly inserts/updates family categories through RLS.
- Debt service currently supports simple borrowed/lent creation, payments, and limited metadata updates.
- `docs/22_family_auth_permissions_plan.md` is the source of truth for Supabase-compatible member invitation and password flows.

## Global Rules

- Do not expose `service_role` in browser code, Vite env, React pages, or client services.
- Do not create or mutate `auth.users` from the browser.
- Invitation/admin Auth operations must happen only in Supabase Edge Functions.
- Financial operations must stay atomic and database-authoritative.
- Do not add direct client writes to financial tables where an RPC is required.
- Do not hard-delete financial history.
- Preserve RLS family isolation.
- All role/invitation changes must be audited.
- Make every migration idempotent where reasonable.
- Add SQL verification tests for security and negative cases.
- Keep UI Arabic-first, RTL, mobile-first, and use friendly language.

## Implementation Priority

Implement in this order:

1. Family administration and permissions.
2. Category governance.
3. Debt/loan expansion.

Do not start the next area until the previous area has migrations, services/types, UI, and verification notes.

---

## Phase 1: Family Administration And Supabase Auth-Compatible Invitations

### Database

Create a new migration after `00030`.

Add:

- `family_invitation_status` enum: `PENDING`, `ACCEPTED`, `EXPIRED`, `REVOKED`.
- `family_invitations` table:
  - `id uuid primary key default gen_random_uuid()`
  - `family_id uuid not null references public.family_groups(id) on delete cascade`
  - `email text not null`
  - `role public.member_role not null`
  - `display_name text`
  - `status public.family_invitation_status not null default 'PENDING'`
  - `invited_by uuid references public.family_members(id) on delete set null`
  - `accepted_by_user_id uuid references auth.users(id) on delete set null`
  - `expires_at timestamptz not null`
  - `created_at timestamptz not null default now()`
  - `accepted_at timestamptz`

Constraints and indexes:

- Normalize email with a trigger or generated/check pattern using `lower(trim(email))`.
- Add a unique partial index so each family has at most one active pending invite per email.
- Prevent `OWNER` invitation if the caller is not OWNER.
- Enable RLS.
- SELECT: family active members can see invitations for their family.
- INSERT/UPDATE should be RPC/Edge Function controlled, not open direct client writes.

Add RPCs:

- `fn_create_family_invitation(p_family_id, p_email, p_role, p_display_name, p_expires_at)`  
  OWNER only. Creates pending invitation and audit event. Used by Edge Function after verifying caller.
- `fn_accept_family_invitation(p_invitation_id)`  
  Authenticated invited user only. Creates or activates the matching `family_members` row.
- `fn_revoke_family_invitation(p_family_id, p_invitation_id)`  
  OWNER only. Sets status to `REVOKED` and audits.
- `fn_change_family_member_role(p_family_id, p_member_id, p_new_role)`  
  OWNER only. Prevent demoting last active OWNER. Audit.
- `fn_suspend_family_member(p_family_id, p_member_id)`  
  OWNER only. Prevent suspending last active OWNER. Audit.
- `fn_reactivate_family_member(p_family_id, p_member_id)`  
  OWNER only. Audit.

Important:

- Current MVP has `uq_family_members_one_active_family_per_user` from `00019_onboarding_rpc.sql`. Study it before accepting invitations. If one user cannot belong to multiple families, document that limitation and make acceptance fail cleanly with a friendly error.
- Do not remove last-owner protection in `00018_immutability_guards.sql`; complement it with explicit RPC checks.

### Edge Function

Create `supabase/functions/family-invite-member/index.ts`.

Function behavior:

- Accept JSON: `{ family_id, email, role, display_name? }`.
- Require `Authorization: Bearer <user-jwt>`.
- Create an authenticated Supabase client with the user's JWT to check caller identity where appropriate.
- Create an admin Supabase client with `SUPABASE_SERVICE_ROLE_KEY` only inside the Edge Function.
- Verify caller is active OWNER of `family_id`.
- Call database RPC `fn_create_family_invitation`.
- Use Supabase Auth Admin API:
  - Prefer `inviteUserByEmail(email, { data: { family_id, invitation_id, role } })`.
  - If project/email configuration requires custom links, use `generateLink` and document that the email provider must send it.
- Return only safe data: invitation id/status/message. Never return service-role details.

### Frontend Services And UI

Add:

- `src/services/familyAdminService.ts`
- Family settings page.
- Members list.
- Pending invitations list.
- Invite member form.
- Change role confirmation.
- Suspend/reactivate confirmation.
- Account security page for password change.
- Forgot-password and update-password routes.

Use Arabic labels:

- `OWNER`: `مدير الأسرة`
- `MEMBER`: `عضو يضيف معاملات`
- `VIEWER`: `مشاهدة فقط`

Password rules:

- Signed-in user changes own password with Supabase Auth client `updateUser({ password })`.
- Forgot password uses `resetPasswordForEmail(email, { redirectTo })`.
- After password recovery redirect, show update-password page and call `updateUser({ password })`.
- Family OWNER must not change another user's password.

### Tests

Add SQL tests covering:

- Non-owner cannot create/revoke invitations.
- OWNER can create invitation.
- Duplicate pending invitation for same family/email is rejected or reuses existing invite deterministically.
- Revoked/expired invitation cannot be accepted.
- Accepting invitation creates ACTIVE member.
- Last OWNER cannot be demoted or suspended.
- MEMBER cannot change roles.
- VIEWER cannot call mutating financial RPCs.

---

## Phase 2: Category Governance

Goal: make category management explicit, controlled, and safe.

### Database/RPC

Keep system categories immutable.

Add RPCs:

- `fn_create_family_category`
- `fn_update_family_category`
- `fn_archive_family_category`
- Optional: `fn_reassign_category_usage` if archiving a used category needs replacement.

Rules:

- OWNER only for category governance.
- Cannot update system categories where `family_id is null` or `is_system = true`.
- Validate parent category belongs to same family or is system, and has the same direction.
- Validate direction/behavior/priority.
- Prevent archiving a category used by active budget/commitment unless a replacement category is provided or the user confirms a safe inactive-only archive.
- Audit changes.

### Services/UI

Replace direct category `.insert()` / `.update()` with RPC calls.

Add a category management page:

- Tabs/filters: دخل، مصروف، تحويل.
- Show system vs family categories.
- Create/edit/archive family category.
- Priority and behavior controls.
- Clear Arabic labels and warnings.

### Tests

- MEMBER cannot create/update/archive categories.
- OWNER can manage family categories.
- System category update/archive is rejected.
- Cross-family parent category is rejected.
- Direction mismatch parent is rejected.

---

## Phase 3: Debt And Loan Expansion

Goal: move debt handling from simple amount tracking to a richer Egyptian household debt model while preserving ledger integrity.

### Product Model

Support:

- Borrowed from someone: liability.
- Lent to someone: receivable.
- Workplace advance.
- Store/installment plan.
- Card/finance installment.
- Informal family debt.
- Gam'eya-created debt stays compatible with current gameya flows.

### Database

Extend carefully without breaking existing data:

Consider adding:

- `debt_kind`: `PERSONAL`, `WORK_ADVANCE`, `INSTALLMENT`, `CARD`, `STORE_CREDIT`, `GAMEYA`, `OTHER`.
- `counterparty_phone text`
- `counterparty_notes text`
- `start_date date`
- `next_due_date date`
- `installment_count int`
- `installments_paid int`
- `payment_schedule_type`: `ONE_TIME`, `MONTHLY_INSTALLMENT`, `FLEXIBLE`
- `priority_level int`
- `is_payroll_deducted boolean`
- `source_reference_type text`
- `source_reference_id uuid`

If adding enums, add them in a new migration. Do not rewrite old enum definitions in `00001`.

Add a debt events/history table if needed:

- `debt_events`: metadata changes, reschedules, write-off notes, non-financial status changes.

### RPCs

Do not rely on direct updates for financial fields.

Add/adjust RPCs:

- `fn_update_debt_metadata`
- `fn_reschedule_debt`
- `fn_write_off_debt`
- `fn_record_debt_payment` enhancements if needed
- Optional `fn_record_payroll_deducted_debt_payment` for salary deducted at source, preserving gross-income reporting.

Rules:

- All money movement must create ledger transactions.
- `remaining_amount` changes only through controlled RPCs.
- Write-off must be explicit, audited, and not delete prior history.
- Debt payment must lock wallet/debt rows deterministically.
- Safe-to-spend must include current-cycle debt obligations consistently.

### UI

Improve debts pages:

- Debt list grouped by:
  - علينا
  - لنا
  - متأخر
  - أقساط قادمة
- Debt details page with:
  - remaining amount
  - original amount
  - next due date
  - payment history
  - linked wallet movements
  - notes/history
- Create debt form with simple and advanced mode.
- Payment/reschedule/write-off flows with confirmations.

### Tests

- Borrowing increases wallet and creates liability.
- Lending decreases wallet and creates receivable.
- Payment reduces remaining amount and creates correct ledger transaction.
- Overpayment is rejected.
- Write-off is audited and does not delete ledger.
- Payroll deduction scenario preserves gross income reporting if implemented.
- Safe-to-spend deducts the right current-cycle debt obligation.

---

## Final Verification Required

Run:

- `npm run build`
- `npm run typecheck` if available separately
- Relevant SQL tests in `supabase/tests`
- New family/invitation/category/debt SQL tests

If Supabase CLI or network/project access is unavailable, state exactly what was not run and why.

## Deliverables

Return:

- Files changed.
- Migrations added.
- Edge Functions added.
- UI routes added.
- Tests added and results.
- Any known limitations, especially around one-active-family-per-user and Supabase email configuration.

