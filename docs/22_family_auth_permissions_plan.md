# Family Auth, Invitations, And Permissions Plan

**Date checked:** 2026-05-05  
**Decision:** Family administration must integrate with Supabase Auth through server-side Edge Functions for invite/admin operations, while role changes and membership rules remain enforced by Postgres RPCs, RLS, and audit events.

## Official Supabase Assumptions Checked

- Supabase Auth Admin APIs require the `service_role` key and must run only on a trusted server, never in the browser: https://supabase.com/docs/reference/javascript/admin-api
- Inviting a user by email is available through `supabase.auth.admin.inviteUserByEmail`: https://supabase.com/docs/reference/javascript/auth-admin-inviteuserbyemail
- Admin-generated invite/recovery links are available through `supabase.auth.admin.generateLink`: https://supabase.com/docs/reference/javascript/auth-admin-generatelink
- A signed-in user can update their own password with `supabase.auth.updateUser` / `supabase.auth.update`: https://supabase.com/docs/reference/javascript/auth-update
- Password recovery is a two-step flow: send reset email, then update password after recovery session: https://supabase.com/docs/reference/javascript/auth-resetpasswordforemail

## Core Architecture

### 1. Member Invitation Flow

Invitation must be handled by a Supabase Edge Function, not by the browser and not by direct inserts into `auth.users`.

Required flow:

1. OWNER opens family members screen.
2. OWNER enters email, display name, and desired role.
3. Client calls Edge Function, for example `family-invite-member`.
4. Edge Function verifies the caller's JWT and confirms the caller is active OWNER of the target family.
5. Edge Function creates a pending invitation record in public schema.
6. Edge Function uses Supabase Auth Admin API to send an invite email or generate an invite link.
7. If the invited email already belongs to a Supabase user, the function links the existing user after acceptance or records a reusable pending invitation.
8. When the user accepts/signs up, a database RPC finalizes membership.

Reason:

- The invited person may not have an app account yet.
- The `service_role` key is required for admin invite operations.
- Membership rows must not be blindly created for unknown/nonexistent auth users.

### 2. Required Database Additions

Add a `family_invitations` table:

- `id`
- `family_id`
- `email`
- `role`
- `display_name`
- `status`: `PENDING`, `ACCEPTED`, `EXPIRED`, `REVOKED`
- `invited_by`
- `accepted_by_user_id`
- `expires_at`
- `created_at`
- `accepted_at`

Rules:

- Only active OWNER can create/revoke invitations.
- Invitation email should be normalized with `lower(trim(email))`.
- One active pending invitation per family/email.
- Invitations expire.
- All changes are audited.

### 3. Permission Changes

Role changes must be implemented through a Postgres RPC, not direct table updates from the UI.

Required RPCs:

- `fn_change_family_member_role(p_family_id, p_member_id, p_new_role)`
- `fn_suspend_family_member(p_family_id, p_member_id)`
- `fn_reactivate_family_member(p_family_id, p_member_id)`
- `fn_revoke_family_invitation(p_family_id, p_invitation_id)`

Rules:

- Caller must be active OWNER.
- Cannot demote, suspend, or remove the last active OWNER.
- Cannot change role of members outside caller's family.
- VIEWER remains read-only by RLS and RPC checks.
- MEMBER can record allowed financial operations, but cannot manage family, budgets governance, categories governance, or sensitive settings unless explicitly allowed later.
- Every permission change creates an audit event.

### 4. Password Change And Recovery

Password management should follow Supabase Auth:

- Signed-in user changes their own password from account settings using `supabase.auth.updateUser({ password })`.
- Forgotten password uses `supabase.auth.resetPasswordForEmail(email, { redirectTo })`.
- After recovery redirect, the app shows an update-password page and calls `supabase.auth.updateUser({ password })`.
- Admins/owners must not set another family member's password from the Mezan UI.

Reason:

- Passwords are identity data, not family finance data.
- Supabase Auth should remain the source of truth for credentials.
- Family OWNER permissions must not become identity-provider admin permissions.

## Edge Function Boundary

Edge Functions may use:

- User JWT for caller identity.
- Supabase service role only inside the function.
- Auth Admin API for invitations and generated links.
- Database RPCs for membership/invitation state changes where possible.

Edge Functions must not:

- Return service role keys or admin details.
- Trust `family_id` without checking caller ownership.
- Create financial data directly.
- Bypass audit events.

## Client UI Scope

Add screens:

- Family settings.
- Members list.
- Pending invitations list.
- Invite member form.
- Change role confirmation.
- Suspend/reactivate member confirmation.
- Account security page for password change.
- Forgot-password and update-password routes.

The UI should show plain Arabic role labels:

- OWNER: "مدير الأسرة"
- MEMBER: "عضو يضيف معاملات"
- VIEWER: "مشاهدة فقط"

## Verification Checklist

- Non-owner cannot invite members.
- MEMBER cannot change another member's role.
- VIEWER cannot create transactions through RPCs.
- Last active OWNER cannot be suspended or demoted.
- Invite unknown email sends/creates Supabase-compatible invitation.
- Existing user invitation does not create duplicate users.
- Revoked/expired invitation cannot be accepted.
- Password change works only for signed-in current user.
- Password recovery redirect lands on the app update-password route.
- No service role key is present in browser code or Vite env exposed to client.
