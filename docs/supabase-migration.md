# Firebase → Supabase migration plan

Status: **complete.** Backend is Supabase; Firebase is used only for FCM delivery. This document is kept as the record of the migration plan.
[`supabase/schema.sql`](../supabase/schema.sql).

## Decisions to confirm first
1. **Existing users?** If the app is still in development, do a clean cut-over
   (no data/auth migration). If there are real users, see "Data migration".
2. **Push notifications:** keep FCM for delivery (Supabase has no mobile push).
   Sending moves to a Supabase Edge Function; no Firebase Blaze plan needed.
3. **Firebase Storage:** the app currently stores thumbnails/bitmaps; confirm
   whether any exist worth migrating.

## Service mapping
| Firebase | Supabase |
|---|---|
| Auth (email/password, reset) | Supabase Auth |
| Firestore `users` | `profiles` (+ `device_tokens` for FCM, owner-only) |
| Firestore `couples`, `inviteCodes` | `couples`, `invite_codes` + RPCs |
| Firestore moods / memories / milestones / notifications | tables of the same name |
| RTDB `presence`, `touch` | Realtime Presence / Broadcast on private channel `couple:<id>` |
| RTDB `mood/.../current` | latest row of `moods` (+ Postgres-changes subscription) |
| RTDB `canvas` strokes + `clearedAt` | live chunks on Broadcast; finished strokes in `canvas_strokes`; `canvas_state` |
| RTDB `members` + rules | `is_couple_member()` helper + RLS + `realtime.messages` policies |
| `firestore.rules` / `database.rules.json` | RLS policies in `schema.sql` |
| Storage | Storage bucket `memories` |

## Schema highlights (improvements over today)
- **Disconnect is enforced in the database.** `couples` has no client
  write policy; `disconnect_couple` is the only way to end a couple, and either
  partner can call it without the other's confirmation.
- **Pairing is a single transaction** (`join_with_code`), replacing the
  multi-step client writes and the awkward "set partner's coupleId" rule.
- **Profiles are no longer world-readable** (partner only) and **FCM tokens are
  never readable by a partner.**
- `profiles.couple_id` is not client-writable (column-level grant).
- Notifications can only be created as yourself, inside your active couple.

## Phases
**0. Setup** — create the Supabase project, apply `schema.sql` to a branch/dev
project, add `supabase_flutter`, init in `main.dart`. Keep `firebase_messaging`.

**1. Auth** — new `SupabaseAuthSource`; reimplement `AuthRepository`
(sign up passes `username`/`avatar_emoji` as user metadata → trigger creates
the profile). Replace `FirebaseAuth.instance.currentUser` in `RouteGuards`,
`main.dart`, `ProfileScreen`, etc. with `Supabase.instance.client.auth`.
Password reset: configure redirect URL / deep link.

**2. Durable data** — `SupabaseSource` replacing `FirestoreSource`; port
`CoupleRepository` (RPCs), `MoodRepository`, `MemoryRepository`,
`NotificationRepository`, timeline queries. Models switch to snake_case
columns and `timestamptz`. `watch*` streams → `.stream(primaryKey: ['id'])`
or realtime channels.

**3. Realtime** — port `presence`, `touch`, `canvas`:
- Presence/online: Realtime Presence on `couple:<id>`.
- Touch: Broadcast events; no `onDisconnect`, so rely on Presence leave +
  a short client-side timeout.
- Canvas: stroke chunks over Broadcast (same chunk model as today), persist the
  completed stroke to `canvas_strokes`; late joiners load strokes then
  subscribe. **This is the riskiest phase** — the current sync is tuned to RTDB
  latency; prototype and measure before committing.

**4. Storage** — bitmap upload to the `memories` bucket via signed URLs.

**5. Push** — database webhook on `notifications` insert → Edge Function that
looks up the partner's `device_tokens` row and calls FCM HTTP v1. The service
account key is a Supabase secret; the function verifies sender and recipient
are the same couple. Client keeps `PushNotificationService`; token upsert moves
to `device_tokens`.

**6. Cut-over & cleanup** — remove `firebase_auth`, `cloud_firestore`,
`firebase_database`; delete `firestore.rules`, `database.rules.json`,
`firestore_source.dart`, `rtdb_source.dart`, `firebase_auth_source.dart`. Keep
`firebase_core`/`firebase_messaging`.

## Data migration (only if there are real users)
- **Auth:** export with `firebase auth:export`, import into Supabase Auth
  (Firebase scrypt hashes are supported by the import tooling), keeping uids
  or mapping old→new uuids (Firebase uids aren't uuids, so a mapping table is
  needed, and all foreign keys must use the new ids).
- **Firestore:** one-off script (Node/Python, service accounts on both sides)
  reading each collection and inserting transformed rows; convert ISO strings
  to `timestamptz`; map ids.
- **RTDB:** ephemeral — don't migrate, except canvas strokes if you want
  existing drawings.
- Do a dry run into a Supabase branch, verify counts, then run for real during
  a short maintenance window with a forced app update.

## Risks
- Canvas/touch latency on Realtime vs RTDB (phase 3).
- Realtime private-channel RLS requires `realtime.messages` policies and
  `private: true` on every channel; easy to misconfigure — test with two users.
- No `onDisconnect` equivalent for touch state.
- Existing installed app versions break at cut-over; ship via forced update.
- The `milestone_type` enum in the schema is a placeholder; align it with the
  app's `MilestoneType` before applying.

## Suggested next step
Review `schema.sql`, then create a Supabase project (or give me the project)
so I can apply it to a branch, generate typed models, and start phase 0–1.
