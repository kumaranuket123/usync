# ADR 0003: Security enforced in the database

Status: accepted

**Decision.** Never trust the client. RLS on every table, scoped by couple membership; column-level grants limit what clients can update (`security_hardening.sql`); couple state changes only through `SECURITY DEFINER` RPCs; private storage bucket with signed URLs; Realtime channel access via `realtime.messages` policies; Android backup restrictions.

**Consequences.** A compromised or modified client cannot read another couple's data. Every schema change needs a policy review, enforced by the `add-supabase-migration` skill and `rls-security-reviewer` agent.
