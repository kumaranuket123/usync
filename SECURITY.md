# Security

## Model
- Auth: Google sign-in only, exchanged for a Supabase session.
- Authorisation: Postgres RLS on every table (`is_couple_member`, `is_active_couple_member`), column-level grants, RPC-only couple state changes. See [ADR 0003](docs/adr/0003-rls-first-security.md) and `supabase/migrations/security_hardening.sql`.
- Storage: private `memories` bucket, signed URLs.
- Realtime: private channel `couple:<id>`, policies on `realtime.messages`.
- Device: optional biometric app lock; Android backup restricted.
- Secrets: FCM service account is a Supabase secret, never in the repo. Only public client IDs are committed.

## Reporting
Please open a private security advisory on the GitHub repository rather than a public issue.
