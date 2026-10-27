---
name: add-supabase-migration
description: Create a Supabase schema change safely (table, column, policy, RPC) with RLS and least-privilege grants. Use for any change under supabase/.
---

# Add a Supabase migration

1. Inspect current tables/policies first (Supabase MCP `list_tables`, or `supabase/schema.sql` plus earlier migrations).
2. Write `supabase/migrations/<snake_case_name>.sql`, idempotent where possible (`if not exists`, `drop policy if exists`).
3. Every new table: `enable row level security`, `couple_id` column, policies using `is_couple_member` / `is_active_couple_member`, separate policies per command (avoids multiple permissive SELECT policies, see `perf_tuning.sql`).
4. Grant clients only needed columns (`revoke update ... ; grant update (col)`), as in `security_hardening.sql`.
5. Couple state changes go through `SECURITY DEFINER` RPCs with `set search_path = ''`, never direct writes.
6. Index foreign keys.
7. Apply with the Supabase MCP `apply_migration`, then run `get_advisors` (security and performance) and fix findings.
8. Update `supabase/schema.sql` if it is the canonical snapshot, and the relevant `docs/features/*.md`.
