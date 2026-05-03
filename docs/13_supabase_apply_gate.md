# Supabase Apply Gate

**Date:** 2026-05-01  
**Status:** Do not apply migrations yet.

## Current Environment

`.env` exists and contains Supabase client connection values. Do not print, commit, or share secrets.

The project is not yet intentionally linked/applied to the target Supabase database.

## Before Applying

Required gates:

1. Add auth/onboarding migration.
2. Review auth/onboarding migration.
3. Decide whether first family creation is RPC-only.
4. Run migrations on a disposable test database first.
5. Run verification SQL scripts.
6. Only then apply to the intended Supabase project.

## Apply Safety Rules

- Do not run `supabase db push` against the target project until explicitly approved.
- Do not use production-like secrets in logs.
- Do not paste `.env` values into prompts or reports.
- Prefer a disposable Supabase project for first execution.
- Capture the exact migration output and verification output.

## MCP Note

If a Supabase MCP tool is available in Antigravity, use it only after confirming the target project and operation. Schema-changing operations require explicit approval.

