# Feature: Subscription groundwork (version gate + access state)

Not user-visible yet. It prepares every installed copy of the app for a future subscription while changing **nothing** for anyone today: `app_config.paywall_enabled` is `false`, so every couple has full access.

Why it exists: an installed APK cannot be recalled or forced to update. The only control over old copies is the server, and only through rules the old copy already knows about. So the hooks ship first, before more APKs go out.

---

## 1. Server switches (`app_config`)

One row, readable only through the RPC `get_app_config()` (also callable before sign-in):

| Field | Meaning |
|---|---|
| `min_supported_build` | Builds below this must update (see "Update screen") |
| `latest_build`, `update_url` | Where to get the newest version (a Play link or an APK download page) |
| `paywall_enabled` | Master switch. `false` = everyone free |
| `trial_days` | Length of the free trial, from account creation |
| `grandfather_before` | Optional: every profile created before this moment counts as grandfathered (for people who joined after the first backfill) |

The table refuses a minimum build with no `update_url`, and any link that is not `https://`, so nobody can be stranded on a dead-end update screen.

Change them in the Supabase SQL editor, e.g. `update public.app_config set min_supported_build = 7, update_url = 'https://...';`. Clients cannot read or write the table.

## 2. Update screen

`SplashBloc` asks `IAccessRepository.getConfig()` while the logo plays. If the installed build number (`PackageInfo.buildNumber`, the number after `+` in `pubspec.yaml`) is below `min_supported_build`, it goes to `/update-required` (`UpdateRequiredScreen`): a blocking page (no back button) with **Update now**, which opens `update_url`. The route guard lets this page through for signed-in and signed-out users alike.

It never locks anyone out by accident: the last server answer is saved on the phone, and with no connection and nothing saved the config is "open" (no minimum, no paywall).

Only builds that contain this check can be gated, so APKs given out before it shipped cannot be.

## 3. Who is free: access state

Decided on the server by `couple_access(couple)` (exposed to members as `get_access`), in this order:

1. Paywall off -> `free`.
2. Either partner is **grandfathered** (`profiles.grandfathered`) -> `grandfathered`.
3. Either partner's `profiles.premium_until` in the future -> `premium` (whoever pays covers the couple while they are in it).
4. The couple's trial still running -> `trial`. The trial is counted **per person** from account creation (`profiles.created_at + trial_days`); a couple's trial runs from its newest member.
5. Otherwise `expired`.

Grandfathering and the trial belong to the **person**, not the couple, because disconnecting and re-pairing creates a new couple row: otherwise an early user would lose their status, or anyone could restart a trial. Every profile that existed when `access_control.sql` ran is grandfathered. To grandfather people who joined later (for example friends who got the APK afterwards), set `app_config.grandfather_before` to the launch time before switching the paywall on.

`premium_until` and `grandfathered` can only be written by the service role (a later payment webhook): clients may update only `username`, `avatar_emoji` and `silent_types` on profiles.

### Known limits (decide before charging)

- Deleting an account and signing up again with the same Google account makes a new profile: it loses grandfathering and gets a fresh trial. Fixing it needs something that survives deletion (such as a hash of the email), which conflicts with the "delete everything" promise unless the privacy policy says so.
- A new Google account is always a new trial.
- A couple's trial runs from its **newest** member, so a user whose trial ended can pair with a brand-new account and get a fresh one. Using the oldest member instead would close that but shorten a genuine newcomer's trial.
- A partner of a grandfathered user is free while they are together; if they disconnect and re-pair, that partner falls back to their own trial.
- Nothing is enforced on the server yet, so old builds that never call `get_access` stay free; only `min_supported_build` can make them update.

## 4. In the app (display only; the server is the authority)

- `Access` / `AccessStatus` (`domain/entities/access.dart`), `AppConfig` (`domain/entities/app_config.dart`), `IAccessRepository` / `AccessRepository` (`getConfig`, `getAccess`; both fail open and never throw).
- **Profile -> YOUR CONNECTION -> Subscription** row: hidden until the paywall is on. Then it shows the state ("Early member", "Free trial: N days left", "Premium until ...", "Your free trial has ended") and opens `/paywall` (`PaywallScreen`). The purchase button there is switched off ("coming soon").
- Nothing is blocked yet. Enforcing "expired = read-only" is the next step (below).

## Not built yet (separate step, when you are ready to charge)

- Server enforcement: extend `is_active_couple_member` with the access check so an expired couple becomes read-only (it can still see and export its memories) on every build, then set `paywall_enabled = true`. **Pairing, sign-out, disconnect and delete-account must never be blocked by an expired state**, and an unpaired user has no couple to ask `get_access` about, so the app has to treat "no couple" as not gated.
- Payments and a webhook that sets `premium_until`. Google Play Billing only works for apps installed from Play, so APK users would need an external checkout; if the app is later listed on Play, Play-installed builds must use Play Billing.
- Who pays for a couple, and what happens to a subscription when the couple disconnects.
- Terms, refund text and a privacy-policy update.

## Code

`supabase/migrations/access_control.sql`, `lib/domain/entities/{app_config,access}.dart`, `lib/domain/repositories/i_access_repository.dart`, `lib/data/repositories/access_repository.dart`, `lib/data/models/{app_config,access}_model.dart`, `lib/presentation/features/access/screens/{update_required,paywall}_screen.dart`, `SplashBloc`, `RouteGuards`.
