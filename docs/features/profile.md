# Feature: Profile

The user's personal space within the shared couple world. Shows identity, relationship stats, and acts as the navigation hub for settings, timeline, widgets, and themes. Also hosts the Notifications screen (accessible from any screen via the bell icon on HomeScreen).

---

## Screens

### ProfileScreen (`/profile`)

Bottom-nav tab (🦋 Profile). Scrollable — hero section is fixed-height, everything below scrolls.

**Layout:**
1. Mesh gradient background
2. Ambient purple glow blob (top, centred, 300×200 px, blurred) — `RadialGradient` inside a `Container` with `BoxDecoration`
3. **Hero section** (non-scrolling, 240 px approx):
   - Spinning avatar ring (`ConicOrbPainter`, 96 px, 22 s, very slow)
   - Inner dark circle (76 px) with avatar emoji (38 px)
   - Username (22 px bold)
   - "Together since [date]" (13 px muted)
   - 3-stat row: Streak / Moments / Doodles
4. **Scrollable body** (below hero):
   - Section label: "YOUR CONNECTION"
   - Row: **Relationship type** (Together / Long-distance, shared with the partner; see [relationship-mode](relationship-mode.md))
   - Row: **Subscription** (only once the paywall is switched on; see [subscription-groundwork](subscription-groundwork.md))
   - Row: **Bucket list** (see [bucket-list](bucket-list.md))
   - Navigation rows: Timeline, Memory Space, Widgets
   - Section label: "PREFERENCES"
   - Navigation rows: Themes, Settings
   - Section label: "DEV" (debug builds only)
   - Navigation row: Empty State Demo
5. `UsyncBottomNav`

---

### StatItem (widget)

Centred column inside a `GlassCard`:
- Value: 22 px bold, gradient text
- Label: 10 px muted, uppercase, letter-spacing 1

Three `StatItem` widgets in an equal-width `Row` with spacing.

---

### ProfileRow (widget)

Full-width tappable row:
- Left: icon container (38×38, `BorderRadius.circular(12)`, type-coloured background)
- Centre: title (15 px white) + subtitle (12 px muted) in a `Column`
- Right: `›` chevron (muted)
- `InkWell` with `onTap` → navigation or action

Used for all navigation items in the scrollable body.

---

### NotificationsScreen (`/notifications`)

Pushed onto the navigation stack from the bell icon on HomeScreen's header. Not a bottom-nav tab.

**Layout:**
1. Mesh gradient background
2. Header row:
   - `NeonBackButton`
   - "Moments" title (the friendlier name for notifications in Usync)
3. `ListView` of `NotifItem` widgets (scrollable)

**NotifItem (widget):**
- Left: icon container (44×44 circle) with type emoji + type-coloured background
- Centre: notification text (14 px, 1.5 line height) + timestamp (12 px muted)
- Right: `UnreadDot` — 8 px pink glowing dot, hidden if `isRead == true`
- Unread items: background tinted `primary.withOpacity(0.055)`, border `primary.withOpacity(0.15)`
- Tap → marks as read + context-appropriate navigation

**Notification types and icons:**
| Type | Icon | Background |
|---|---|---|
| touch | 👆 | `rgba(255,45,120,.12)` |
| doodle | ✏️ | `rgba(0,212,255,.12)` |
| moodChange | 💭 | `rgba(155,78,221,.12)` |
| streak | 🔥 | `rgba(255,215,0,.10)` |
| milestone | 💖 | `rgba(199,125,255,.12)` |
| sleep | 🌙 | `rgba(0,212,255,.10)` |

---

## User Flows

### Viewing Profile
```
User taps Profile tab
  → ProfileBloc.ProfileLoaded dispatched
  → Fetch User + Couple from repositories
  → ProfileState: user, couple, stats
  → Hero section renders with live data
```

### Viewing Stats
Stats are computed from cached data, not live streams:
- **Streak:** `couple.streakDays` (updated daily by Cloud Function)
- **Moments:** `couple.totalMoments` (incremented on each Memory save)
- **Doodles:** `count of memories where type == canvas` — queried once on profile load

### Navigating from Profile
```
"Relationship Timeline" tapped → GoRouter.push('/timeline')
"Memory Space" tapped          → GoRouter.go('/memories')   (switch tab)
"Widgets" tapped               → GoRouter.go('/widgets')     (switch tab)
"Themes" tapped                → GoRouter.push('/themes')
"Settings" tapped              → GoRouter.push('/settings')
```

### Viewing Notifications
```
HomeScreen bell icon tapped
  → GoRouter.push('/notifications')
  → NotificationBloc.NotificationsLoaded
  → Firestore query: /notifications/{coupleId}/items, orderBy timestamp desc, limit 50
  → NotifState.items rendered

User taps a NotifItem
  → if isRead == false: NotificationBloc.NotificationRead(id)
      → Firestore update({isRead: true})
  → Navigate based on type:
      touch     → /touch-sync
      doodle    → /canvas
      moodChange → /home (mood visible on home)
      streak    → /timeline
      milestone → /memories
```

### Mark All Read
```
(Future: "Mark all read" button in header)
  → NotificationBloc.AllRead
  → Firestore batch update: all items where isRead == false → set isRead = true
  → NotifState.unreadCount = 0
```

### Avatar Change (v1.1 scope)
```
Profile avatar tapped
  → bottom sheet with avatar emoji grid
  → AvatarSelected(emoji)
  → Firestore /users/{uid} update({avatarEmoji: emoji})
  → ProfileState.user.avatarEmoji updates
```

---

## API Requirements

### Firestore — User + Couple data

| Operation | Path | Purpose |
|---|---|---|
| `get` | `/users/{uid}` | Load own user data |
| `get` | `/couples/{coupleId}` | Load relationship stats |
| `query count` | `/memories/{coupleId}/items where type == canvas` | Doodle count stat |
| `update` | `/users/{uid}` | Avatar change (v1.1) |

### Firestore — Notifications

| Operation | Path | Purpose |
|---|---|---|
| `query(limit:50, orderBy: timestamp desc)` | `/notifications/{coupleId}/items` | Load notification list |
| `update({isRead: true})` | `/notifications/{coupleId}/items/{id}` | Mark single read |
| `batch update` | `/notifications/{coupleId}/items` | Mark all read |
| `snapshots()` | `/notifications/{coupleId}/items where isRead == false` | Unread count badge stream (bell icon on HomeScreen) |

The unread count stream is held in `NotificationBloc` and shared upward to `HomeScreen` via `BlocBuilder`.

---

## Data Models

### `NotificationItem` (domain entity)
```
id:        String
coupleId:  String
type:      NotifType     // enum: touch, doodle, moodChange, streak, milestone
bodyText:  String        // pre-formatted human-readable string
isRead:    bool
timestamp: DateTime
```

### `NotifType` enum
```dart
enum NotifType { touch, doodle, moodChange, streak, milestone }
```

Extension: `icon` (emoji), `backgroundColor` (Color).

### `NotificationItemModel` (data layer — Firestore)
```json
{
  "id":        "notif_abc",
  "coupleId":  "couple_xyz",
  "type":      "moodChange",
  "bodyText":  "Aria's mood changed to \"Thinking About You\" 💭",
  "isRead":    false,
  "timestamp": "2026-05-30T21:00:00Z"
}
```

### Profile stats (computed, not persisted as a model)
```
streakDays:    int    // from Couple.streakDays
totalMoments:  int    // from Couple.totalMoments
doodleCount:   int    // queried from Memory collection
```

---

## BLoC: `ProfileBloc`

**Provided at:** `ProfileScreen` subtree.

### Events
```
ProfileLoaded
AvatarChanged  { emoji: String }    // v1.1
StatsRefreshed
```

### States
```
ProfileLoading
ProfileReady {
  user:         User
  couple:       Couple
  doodleCount:  int
}
ProfileError { message: String }
```

### Handler: `ProfileLoaded`
1. Emit `ProfileLoading`
2. Parallel fetch: `IAuthRepository.getCurrentUser()` + `ICoupleRepository.getCouple(coupleId)`
3. Query doodle count from Firestore
4. Emit `ProfileReady`

---

## BLoC: `NotificationBloc`

**Provided at:** `NotificationsScreen` subtree. The unread count stream is a separate concern — read via a `StreamProvider` or embedded in `HomeBloc`.

### Events
```
NotificationsLoaded
NotificationRead    { id: String }
AllRead
NotificationsUpdated { items: List<NotificationItem> }
```

### States
```
NotifLoading
NotifReady {
  items:        List<NotificationItem>
  unreadCount:  int
}
NotifError { message: String }
```

### Handler: `NotificationsLoaded`
1. Emit `NotifLoading`
2. Subscribe to Firestore snapshot stream
3. On each emission → dispatch `NotificationsUpdated`

### Handler: `NotificationRead(id)`
1. Optimistic: flip `isRead` in state
2. Firestore update
3. Recompute `unreadCount`

---

## Shared Widgets Used

| Widget | Screen | Usage |
|---|---|---|
| `ConicOrbPainter` | ProfileScreen | Spinning avatar ring |
| `GlassCard` | ProfileScreen | StatItem containers |
| `GradientText` | ProfileScreen | Stat values |
| `MeshGradientPainter` | Both | Background |
| `NeonBackButton` | NotificationsScreen | Back navigation |
| `UsyncBottomNav` | ProfileScreen | Persistent footer |
| `LoadingDots` | Both | Loading states |
