# Feature: Settings

App configuration hub: notifications, privacy and security, appearance, storage, and the account actions (disconnect, delete, sign out). Also contains the Theme Selection and Alert Sounds screens. Changes take effect immediately, with no save/cancel step.

---

## Screens

### SettingsScreen (`/settings`)

Pushed from ProfileScreen; not a bottom-nav destination. Header (`NeonBackButton` + "Settings") above a scrolling list grouped by section labels. On open it dispatches `AlertTypesRequested` (once) and provides its own `ProfileBloc`, which owns the disconnect state.

| Section | Row | Control | Behaviour |
|---|---|---|---|
| NOTIFICATIONS | Push notifications | Toggle | `ToggleChanged(key: 'notifications')`. Starts/stops pushes on this device (see below) |
| | Alert sounds | Row -> `/alert-sounds` | Subtitle "N of 6 alerts silent" |
| PRIVACY & SECURITY | Location sharing | Row -> `/location` | See [location](location.md) |
| | Biometric lock | Toggle | `AppLockService.setEnabled`, which requires passing the prompt; if the phone has no screen lock a snackbar explains. See [app-lock](app-lock.md) |
| APPEARANCE & FEEL | Themes | Row -> `/themes` | |
| | Animations | Toggle | Off disables particle/pulse effects |
| | Haptic feedback | Toggle | Read by touch sync before vibrating |
| STORAGE | Save older memories to gallery | Toggle | Asks for photo access first (`Gal.requestAccess`); a refusal leaves the switch off. On success copies already-archived pictures to the "Usync" album and reports how many. Off keeps future ones in the app only; existing gallery copies are kept. See [memories](memories.md) |
| ABOUT | About Usync | Row | Shows the installed version (`package_info_plus`); opens the About screen (`/about`, see [about](about.md)) |
| | Privacy Policy | Row | Opens the public policy in the browser (`openPrivacyPolicy`, `AppConstants.privacyPolicyUrl`, the page `docs/privacy-policy.html` served by GitHub Pages from `main`); a snackbar says so if it cannot open |
| DANGER ZONE | Disconnect Couple | Row (only when `ProfileReady`) | Confirmation dialog, then `ProfileBloc.DisconnectCouple` |
| | Delete Account | Row | Type-DELETE dialog, then `AuthBloc.DeleteAccountRequested` |
| | Sign Out | Outline button | Confirmation dialog, then `AuthBloc.SignOutRequested` |

On `ProfileDisconnected` the screen refreshes the app-wide user (`AuthStateChecked`, which clears `coupleId`) and goes to `/pair-invite`.

### AlertSoundsScreen (`/alert-sounds`)

One switch per alert group, keyed by `NotifType.soundGroup`: `touch`, `doodle`, `moodChange`, `streak`, `milestone`, `question`, `location` (a partner's "locate" request counts as `location`). Each emits `AlertSilenceChanged(group, silent)`. `location` is silent by default (`NotifType.defaultSilent`).

### ThemeSelectionScreen (`/themes`)

Accessible from Settings (`Themes` row) and from ProfileScreen (`Themes` row). Not a bottom-nav destination.

**Layout:**
1. Mesh gradient background
2. Header row:
   - `NeonBackButton`
   - "Themes" title
   - "Choose your emotional palette" subtitle
3. `ListView` of 5 `ThemeCard` widgets (full-width, vertical scroll)

---

### ThemeCard (widget)

Full-width rounded card (110 px tall, `BorderRadius.circular(24)`):
- **Background:** `Stack` with a `LinearGradient` `Container` at 65% opacity (the theme preview gradient)
- **Border:** 2 px solid white when selected, transparent otherwise
- **Content row:**
  - Theme name (18 px bold white)
  - Checkmark circle (28 px): empty border when unselected, white fill + pink check when selected
- **Swatch row:** 4 × 24 px colour dots (white-bordered circles) below the name
- Tap → `ThemeBloc.ThemeChanged(themeId)`

**5 themes and their gradients:**
| ID | Name | Gradient stops |
|---|---|---|
| `midnightPurple` | Midnight Purple | `#2D1B69 → #11998E` |
| `neonPink` | Neon Pink | `#FF2D78 → #6B1FB2` |
| `oceanBlue` | Ocean Blue | `#0575E6 → #021B79` |
| `lavenderDream` | Lavender Dream | `#9B59B6 → #C77DFF` |
| `sunsetGlow` | Sunset Glow | `#FF416C → #FF4B2B → #FFA500` |

---

## User Flows

### Toggle a setting
```
Toggle tapped -> ToggleChanged(key, value)
  -> state updated immediately
  -> PrefsSource.setToggle  (stored as setting_<key>)
```

### Push notifications switch
```
Off -> delete this device's device_tokens row, then FirebaseMessaging.deleteToken()
On  -> FirebaseMessaging.getToken(), RPC register_device_token(token)
Either fails (e.g. offline) -> the toggle is reverted and the reverted value is saved,
                               so the UI shows what is really in effect
```
Affects this device only. Foreground banners are also suppressed while off (`PushNotificationService`).

### Alert sounds
```
AlertSilenceChanged -> state updated optimistically
  -> notifications.setSilentTypes(set)  (profiles.silent_types, one choice for all the user's devices)
  -> on failure the previous set is restored
```
The `send-push` Edge Function reads `profiles.silent_types` and sends quiet types on the low-importance `usync_silent` channel. See [push-notifications](push-notifications.md).

### Disconnect couple
```
Confirm ("unlinks you both right away and permanently deletes everything you shared")
  -> ProfileBloc.DisconnectCouple -> disconnect_couple RPC
```
Either partner can do this alone. The RPC (`disconnect_deletes_data.sql`) deletes moods, memories, milestones, notifications, canvas strokes, locations, question answers, bucket-list items, the next-meet date and streak activity, leaves the `couples` row as an empty tombstone with `disconnected_at` set (so the partner's app sees it via Realtime), resets streak counters and clears both profiles' `couple_id`. Memory images in Storage are removed by the app before the RPC, because SQL cannot delete Storage objects. Pair again with a new code ([pairing](pairing.md)).

### Delete account
```
Dialog: "Type DELETE to confirm" (button enabled only when the text matches, case-insensitive)
  -> AuthBloc.DeleteAccountRequested -> delete_my_account RPC
```
Required by Google Play. Also reachable without pairing, from the `AccountLinks` row on the invite screen (`confirmAndDeleteAccount`, `settings/widgets/delete_account_dialog.dart`). Deletes the user's data in every couple they were in, then the auth user; the partner is left disconnected. Locally saved memory pictures are removed too (`LocalMemoryImages.deleteAll`). Migrations: `delete_account.sql`, `question_of_the_day.sql` (also removes question answers).

### Sign out
```
Confirm -> AuthBloc.SignOutRequested -> SigningOut -> authRepository.signOut() -> Unauthenticated
  -> app.dart / RouteGuards send the user to login
```
The outbox is cleared at sign-out so queued changes are never sent as another account (see [offline](offline.md)).

### Change theme
```
Tap ThemeCard -> ThemeBloc.ThemeChanged(id) -> theme_id saved -> MaterialApp rebuilds
```

---

## Data

### Local (SharedPreferences via `PrefsSource`)

| Key | Type | Default | Description |
|---|---|---|---|
| `setting_notifications` | bool | true | Push on/off for this device |
| `setting_haptic` | bool | true | Haptic feedback |
| `setting_animations` | bool | true | Particle/pulse animations |
| `setting_gallery_backup` | bool | false | Copy archived memory pictures to the gallery |
| `gallery_saved_ids` | string list | empty | Memory ids already copied, so none is saved twice |
| `app_lock` | bool | true | Biometric lock (off if the phone has no screen lock) |
| `location_sharing` | bool | false | Location sharing |
| `theme_id` | string | `midnightPurple` | Active theme |

### Server

| What | Where |
|---|---|
| Alert sound choices | `profiles.silent_types` (text[], default `['location']`) |
| Device push tokens | `device_tokens` (one row per device; `register_device_token` RPC) |
| Couple state | `disconnect_couple`, `delete_my_account` RPCs |

---

## BLoC: `SettingsBloc`

**Provided at:** root `MultiBlocProvider` (app-wide). Depends on `PrefsSource` and `INotificationRepository`.

### Events
```
SettingsLoaded                                  // app start: read local toggles
AlertTypesRequested                             // Settings opened: fetch silent types once
ToggleChanged { key, value }
AlertSilenceChanged { group, silent }
```

### State: `SettingsState`
```
toggles:           Map<String, bool>   // notifications, haptic, animations, gallery_backup
silentTypes:       Set<String>         // groups without sound/popup
silentTypesLoaded: bool
```
Getters: `notificationsEnabled`, `hapticEnabled`, `animationsEnabled`, `galleryBackupEnabled`.

### Handlers
- `SettingsLoaded`: emit toggles from prefs.
- `AlertTypesRequested`: skipped if already loaded; on failure keeps defaults and retries next visit.
- `ToggleChanged`: emit, persist, and for `notifications` apply the push switch (revert on failure).
- `AlertSilenceChanged`: optimistic emit, save to server, restore on failure.

---

## BLoC: `ThemeBloc`

**Provided at:** Root `MultiBlocProvider` (app-wide — `MaterialApp.theme` reads from it).

### Events
```
ThemeLoaded                  // app startup
ThemeChanged { id: String }
```

### States
```
ThemeState {
  activeThemeId: String
  themeData:     ThemeData
}
```

### Handler: `ThemeLoaded`
1. Read `theme_id` from `PrefsSource` (default: `midnightPurple`)
2. Build `ThemeData` from `AppTheme.build(tokens)`
3. Emit `ThemeState(activeThemeId: id, themeData: data)`

### Handler: `ThemeChanged(id)`
1. Validate `id` is a known theme
2. Write `theme_id` to `PrefsSource`
3. Build new `ThemeData`
4. Emit updated `ThemeState`

---

## Shared Widgets Used

| Widget | Usage |
|---|---|
| `NeonBackButton` | Back navigation |
| `GlassCard` | ThemeCard base |
| `UsyncOutlineButton` | Sign Out |
| `ToggleSwitch` | Toggle rows (`shared/widgets/toggle_switch.dart`) |
| `MeshGradientPainter` | Background |
