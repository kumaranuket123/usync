# Feature: Settings

App configuration hub covering account, couple connection, experience preferences, and notifications. Also includes the Theme Selection screen, which is accessible both from Settings and from the Profile navigation row. Settings changes take effect immediately with no save/cancel pattern.

---

## Screens

### SettingsScreen (`/settings`)

Pushed from ProfileScreen. Not a bottom-nav destination.

**Layout:**
1. Mesh gradient background
2. Header row:
   - `NeonBackButton`
   - "Settings" title
3. `ListView` (scrollable, `padding.bottom = 100`):
   - Section: **Account**
   - Section: **Connection**
   - Section: **Experience**
   - Section: **About**
   - Sign Out button (full-width, red-tinted outline)
4. No bottom nav (sub-screen)

---

### Section: Account
| Row | Icon bg | Title | Subtitle | Right |
|---|---|---|---|---|
| Profile | `rgba(255,45,120,.12)` | Profile | username · email | `›` |
| Privacy | `rgba(155,78,221,.12)` | Privacy | Manage visibility | `›` |

**Profile row** → v1.1 (navigate to avatar + username edit screen)
**Privacy row** → v1.1 (placeholder — shows a coming-soon sheet)

---

### Section: Connection
| Row | Icon bg | Title | Subtitle | Right |
|---|---|---|---|---|
| Couple | `rgba(255,110,199,.12)` | Couple Settings | Partner name · paired date | `›` |
| Notifications | `rgba(0,212,255,.10)` | Notifications | Gentle emotional alerts | `Toggle` |

**Couple Settings row** → navigate to `/couple-settings` (v1.1 — rename couple, view invite code)
**Notifications toggle** → `SettingsBloc.ToggleChanged(key: 'notifications', value: bool)`

---

### Section: Experience
| Row | Icon bg | Title | Subtitle | Right |
|---|---|---|---|---|
| Themes | `rgba(255,215,0,.10)` | Themes | Active theme name | `›` |
| Animations | `rgba(155,78,221,.12)` | Animations | Rich particle effects | `Toggle` |
| Dark Mode | `rgba(0,212,255,.10)` | Dark Mode | Always on | `Toggle` (disabled) |
| Haptic | `rgba(255,45,120,.10)` | Haptic Feedback | Vibrate on partner touch | `Toggle` |

**Themes row** → navigate to `/themes`
**Animations toggle** → globally disables `ParticleField`, `PulseRings`, `FloatingReactions` when off (performance mode)
**Dark Mode toggle** → always shows "on", non-interactive (Usync is dark-mode only)
**Haptic toggle** → `SettingsBloc.ToggleChanged(key: 'haptic', value: bool)`

---

### Section: About
| Row | Icon bg | Title | Subtitle | Right |
|---|---|---|---|---|
| About Usync | `rgba(255,255,255,.05)` | About Usync | Version 1.0.0 | `›` |

**About row** → shows a `showAboutDialog` or navigates to a simple about page

---

### Sign Out Button

Full-width `OutlineButton` at the bottom of the scroll list, with red-tinted border and text (`rgba(255,80,80,.7)`). Tap → shows a `showDialog` confirmation → `AuthBloc.SignOutRequested`.

---

### Toggle (widget)

Custom animated toggle (`46×26` px). Not Flutter's `Switch` — custom `GestureDetector`-wrapped `AnimatedContainer`:
- Off: `rgba(255,255,255,.14)` background, circle at left
- On: `LinearGradient(primary, purple)` background + `BoxShadow` glow, circle at right
- Transition: 300 ms, `Curves.easeInOut`

The `Toggle` is a pure stateless widget driven by a `bool` prop + `onChanged` callback. State lives in `SettingsBloc`.

---

## Screens (continued)

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

### Toggling a Setting
```
User taps a Toggle (e.g. Haptic Feedback)
  → Toggle.onChanged(bool newValue)
  → SettingsBloc.ToggleChanged(key: 'haptic', value: newValue)
  → SettingsState.toggleMap updated
  → PrefsSource.setBool('setting_haptic', newValue) (persisted immediately)
  → Toggle animates to new position
  → Effect: TouchSyncBloc checks SettingsState.hapticEnabled before firing HapticFeedback
```

### Changing Theme
```
ThemeSelectionScreen opened
  → ThemeBloc.currentThemeId already loaded (from app startup prefs read)
  → ThemeCard for active theme shows selected state

User taps a different ThemeCard
  → ThemeBloc.ThemeChanged(themeId: 'neonPink')
  → ThemeState.activeThemeId = 'neonPink'
  → PrefsSource.setString('theme_id', 'neonPink')
  → MaterialApp.theme rebuilds via BlocBuilder at root
  → All screens instantly update to new palette
  → ThemeCard selection state updates
```

### Sign Out
```
"Sign Out" button tapped
  → showDialog: "Are you sure you want to sign out?"
  → Confirmed:
      → AuthBloc.SignOutRequested
      → Firebase Auth.signOut()
      → Hive cache cleared
      → PrefsSource: keep onboardingSeen=true, clear auth state
      → GoRouter navigates to /login, removes all previous routes
  → Cancelled: dialog dismisses, no action
```

### Notifications Toggle
```
Notifications toggle tapped → off
  → SettingsBloc.ToggleChanged(key: 'notifications', value: false)
  → PrefsSource.setBool('setting_notifications', false)
  → FirebaseMessaging.deleteToken() (stops FCM delivery)

Notifications toggle → on
  → PrefsSource.setBool('setting_notifications', true)
  → FirebaseMessaging.getToken() → store token in Firestore /users/{uid}/fcmToken
```

### Animations Toggle
```
Animations toggle → off
  → SettingsBloc.ToggleChanged(key: 'animations', value: false)
  → SettingsState.animationsEnabled = false
  → Screens read this setting:
      ParticleField: renders nothing
      PulseRings: renders static rings (no animation)
      FloatingReactions: renders nothing
      PartnerOrb: still spins (core UX, not disabled)
      HeartbeatVisualizer: still animates (core UX)
```

---

## API Requirements

### SharedPreferences (local — all settings persisted locally)

| Key | Type | Default | Description |
|---|---|---|---|
| `setting_notifications` | `bool` | `true` | FCM on/off |
| `setting_haptic` | `bool` | `true` | Haptic feedback enabled |
| `setting_animations` | `bool` | `true` | Particle/pulse animations |
| `theme_id` | `String` | `midnightPurple` | Active theme ID |

### Firebase Messaging (notifications toggle)
| Operation | Trigger |
|---|---|
| `FirebaseMessaging.deleteToken()` | Notifications toggled off |
| `FirebaseMessaging.getToken()` + Firestore update | Notifications toggled on |

### Firestore (FCM token management)
| Operation | Path | Trigger |
|---|---|---|
| `update({fcmToken: token})` | `/users/{uid}` | Notifications re-enabled |

---

## Data Models

### Settings (not a domain entity — local prefs only)

Represented as a simple map in `SettingsState`:
```
toggleMap: Map<String, bool> {
  'notifications': true,
  'haptic':        true,
  'animations':    true,
}
```

### `UsyncTheme` (value object — referenced by ThemeBloc)
```
id:      String            // 'midnightPurple', 'neonPink', etc.
name:    String
tokens:  UsyncThemeData    // ThemeExtension with all color/gradient tokens
```

---

## BLoC: `SettingsBloc`

**Provided at:** Root `MultiBlocProvider` (app-wide — other BLoCs read settings from it).

### Events
```
SettingsLoaded               // app startup — reads all prefs
ToggleChanged { key: String, value: bool }
```

### States
```
SettingsInitial
SettingsReady {
  toggleMap: Map<String, bool>
}
```

### Handler: `SettingsLoaded`
1. Read all setting keys from `PrefsSource`
2. Emit `SettingsReady(toggleMap: {...})`

### Handler: `ToggleChanged(key, value)`
1. Emit updated `SettingsReady` with toggled key
2. Write to `PrefsSource`
3. Side effects:
   - `key == 'notifications'` → `INotificationRepository.toggleFCM(value)`

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

| Widget | Screen | Usage |
|---|---|---|
| `NeonBackButton` | Both | Back navigation |
| `GlassCard` | ThemeCard base | — |
| `GradientText` | — | Not used on settings screens |
| `OutlineButton` | SettingsScreen | Sign Out action |
| `Toggle` | SettingsScreen | 4 toggle rows (defined in shared/widgets/) |
| `MeshGradientPainter` | Both | Background |
