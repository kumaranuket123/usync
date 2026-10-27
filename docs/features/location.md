# Feature: Location

Opt-in sharing of each partner's last known location on a map (`/location`). Nothing is tracked continuously: the position is refreshed when the app opens or returns to the foreground, or when the partner asks for a fresh fix.

---

## Screen: LocationScreen

Map (`flutter_map` + `latlong2`) with the user's and partner's markers, a sharing toggle, a "locate" button to request a fresh partner fix, a background-sharing toggle, and prompts that send the user to system settings when permission or the location service is off.

## State (`LocationBloc`)

States: `LocationConnecting`, `LocationReady { isSharing, isBusy, isLocating, own, partner, access }`.

| Event | Meaning |
|---|---|
| `LocationScreenMounted` | Load both locations, subscribe to the partner's row |
| `LocationSharingToggled` | Turn sharing on (sync own fix) or off (delete own row) |
| `LocateRequested` | Ask the partner's phone for a fresh fix (`isLocating` until it arrives) |
| `BackgroundToggled` / `BackgroundPermissionRechecked` | Opt in/out of answering while the app is closed; re-check after the user returns from settings |
| `PartnerLocationChanged` | Realtime update of the partner's row |
| `LocationRefreshed`, `LocationSettingsRequested` | Manual refresh, open system settings |

`LocationAccess` values: `granted`, `denied`, `deniedForever`, `serviceDisabled`, `backgroundDenied`.

## Data

- `locations` (durable): one row per user (`user_id` primary key), `couple_id`, `latitude`, `longitude`, `accuracy`, `allow_background`, `updated_at`. Added to the `supabase_realtime` publication so the partner's row streams live.
- RLS: members of an active couple can read; a user can insert/update/delete only their own row. `locations_own_row_select.sql` additionally lets a user always read their own row, because the upsert checks the existing row and a stale row from a previous couple caused 403s.
- `LocationRepository.syncOwnLocation` checks permission, reads a high-accuracy fix (15 s limit, falls back to last known), and upserts. `allow_background` is left untouched on conflict.
- Sharing preference is local (`PrefsSource.locationSharing`).

### Refresh paths

1. **App open / resume**: `LocationSyncService` (min 2 min gap), only if sharing is on, never prompts.
2. **Partner "locate"**: `requestPartnerLocation` inserts a `locate` notification. The `send-push` function sends the recipient a visible push (so they always know they were located) plus a silent data push, but only if their `allow_background` is true. The background handler calls `LocationSyncService.answerLocateRequest`, which re-checks `allow_background` and syncs.

Background sharing needs the OS "always" permission; on Android 11+ the user must grant it on the app's permission page, which the app opens and then re-checks.

## Distance elsewhere

Besides the sheet on this screen, long-distance couples see the distance on Home ([long-distance](long-distance.md)); it uses the same saved rows and needs both partners to share.

## Privacy

Opt-in, deletable (turning sharing off removes the row), visible to the partner only, and a locate request is always announced to the person being located. `location` alerts are silent (no sound/popup) by default.
