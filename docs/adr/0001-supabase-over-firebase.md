# ADR 0001: Supabase as backend, Firebase for FCM only

Status: accepted

**Context.** The app started on Firebase (Auth, Firestore, Storage). Couple data is relational (couples, members, invites) and needs row-level access rules that are hard to express in Firestore rules.

**Decision.** Move to Supabase: Postgres with RLS, Auth, Realtime, Storage, Edge Functions. Keep Firebase only for FCM because Supabase has no mobile push. Sending moves to the `send-push` Edge Function, avoiding the Firebase Blaze plan.

**Consequences.** Authorisation lives in SQL policies that can be reviewed and tested. Two vendors remain, but Firebase is confined to token delivery. Migration plan: [supabase-migration.md](../supabase-migration.md).
