# Feature: Home

The primary experience screen. This is the emotional centrepiece of the app — always alive, always reflecting the partner's presence. It is the first screen shown after pairing and the default tab of the bottom navigation.

---

## Screens

### HomeScreen (`/home`)

**Layout (top to bottom):**

1. **Ambient background layer** — `MeshGradientPainter` (3 radial blobs: pink top-right, purple bottom-left, cyan centre)
2. **Background glow blobs** — two `Container` widgets with `BoxDecoration.gradient` + `filter:blur` equivalent (`ImageFiltered` or `BackdropFilter`)
3. **Header row** — greeting text (left) + notification bell (right)
4. **PartnerOrbSection** — the focal element (see below)
5. **HeartbeatVisualizer** — animated EKG line
6. **QuickActionsRow** — 4 glass pills
7. **MoodStrip** — labelled horizontal scroll
8. **FloatingReactions** — 4 emoji drifting upward continuously
9. **UsyncBottomNav** — persistent across main app screens

---

### PartnerOrbSection (widget within HomeScreen)

This is the most visually complex element in the app.

**Layers (centre-outward):**
- Inner dark circle (118 px) — `RadialGradient(bg2, bg1)` — contains partner avatar emoji (50 px)
- Spinning conic-gradient outer ring (150 px) — `ConicOrbPainter`, 14 s rotation, `breathe` overlay (scale 1→1.07 every 4.5 s)
- Online status badge — bottom-right, glass pill with green/grey dot + "online" label, z-indexed above ring
- 3 expanding `PulseRings` (200 / 250 / 300 px) — pink, 3.5 s cycle, staggered 1.1 s each
- Partner name — 22 px bold white, below orb
- Partner mood text — 15 px italic, `primarySoft` colour, below name (live from RTDB stream)

**Glow shadow on orb:**
```
BoxShadow(color: pink.withOpacity(0.35), blurRadius: 50, spreadRadius: 0)
BoxShadow(color: purple.withOpacity(0.2), blurRadius: 100, spreadRadius: 0)
```

---

### HeartbeatVisualizer

`CustomPainter` drawing a fixed EKG polyline across the full width (270 px wide, 48 px tall). The polyline is static (not data-driven in v1). A scan line — a vertical gradient line — travels left to right on a looping `AnimationController` (2 s). The portion of the polyline to the left of the scan line is brighter; the rest is dimmed.

---

### LongDistanceCard

Shown under the quick actions only for long-distance couples: distance apart and a countdown to the shared next-meet date; tap to set it. See [long-distance](long-distance.md).

### QuickActionsRow

Four glass pills in a single `Row`, wrapped in a `FittedBox(scaleDown)` so they stay on one line (and shrink slightly) on narrow screens instead of wrapping and overflowing the Home column:
- 👆 Touch → navigates to `/touch-sync`
- 📍 Location → navigates to `/location`
- 💭 Mood → navigates to `/mood`
- 💬 Question → navigates to `/question` (see [question-of-the-day](question-of-the-day.md))

Each pill is a `GestureDetector`-wrapped `GlassCard` with an icon + label. Active/pressed state tints background to `primary.withOpacity(0.15)`.

---

### MoodStrip

A labelled section ("RECENT MOODS" uppercase, muted) above a `SingleChildScrollView(scrollDirection: Axis.horizontal)` of `MoodChip` widgets. The chip list is populated from `HomeState.recentMoods` (last 10 moods from both partners, merged and sorted by recency).

---

### FloatingReactions

Four emoji (`💖 ✨ 🌸 💜`) positioned at fixed (x, y) coordinates using a `Stack`. Each is driven by a `TweenAnimationBuilder` that animates `dy: 0 → -900` over 5–8 s with staggered start delays (0 / 2 / 1 / 3 s). Each loops via `repeat: true`. Opacity fades in at 10% and out at 90% of the animation timeline using `Opacity` + a custom `CurveTween`.

---

## User Flows

### Entering Home (post-pairing)
```
PairSuccessScreen → tap "Enter your space"
  → navigate to /home
  → UsyncBottomNav becomes visible
  → HomeBloc.HomeStarted dispatched
  → RTDB listeners attached: partner presence + partner mood
  → HomeLoaded state emitted
  → UI builds with live partner data
```

### Partner Comes Online
```
RTDB /presence/{coupleId}/{partnerUid}/isOnline flips to true
  → HomeBloc receives PartnerPresenceUpdated(isOnline: true)
  → HomeState.isOnline updates to true
  → PartnerOrb badge changes colour (grey → green dot)
  → mild haptic: HapticFeedback.lightImpact()
```

### Partner Mood Changes
```
RTDB /mood/{coupleId}/{partnerUid}/current changes
  → HomeBloc receives PartnerMoodUpdated(mood)
  → HomeState.partnerMood updates
  → partner mood text below orb updates with fade transition
  → FloatingReactions temporarily intensifies (1 extra burst emoji)
```

### Notification Bell Tapped
```
HomeScreen header bell icon tapped
  → navigate to /notifications (push, not tab switch)
```

### Quick Action Tapped
```
Any pill tapped → navigate to respective screen via GoRouter push
  → bottom nav remains visible on Canvas
  → bottom nav hidden on Touch Sync, Mood (full-screen experiences)
```

### App Backgrounded / Foregrounded
```
App enters background
  → CoupleRepository.updatePresence(isOnline: false)

App returns to foreground
  → CoupleRepository.updatePresence(isOnline: true)
  → HomeBloc resumes RTDB streams if disposed
```

---

## API Requirements

### Firebase RTDB — Realtime presence & mood

| Path | Type | Operation | Trigger |
|---|---|---|---|
| `/presence/{coupleId}/{uid}/isOnline` | `bool` | `set` | App foreground/background |
| `/presence/{coupleId}/{uid}/isOnline` | `bool` | `onValue` stream | Home mounted |
| `/mood/{coupleId}/{uid}/current` | `MoodModel JSON` | `onValue` stream | Home mounted |

### Firestore — Historical data

| Collection/Doc | Operation | Purpose |
|---|---|---|
| `/users/{uid}` | `get` | Load own user name + avatar |
| `/couples/{coupleId}` | `get` | Load couple.pairedAt, streakDays |
| `/moods/{coupleId}/history` (subcollection) | `query limit 10 orderBy createdAt desc` | Populate MoodStrip |

### AppLifecycleObserver (local)
Listens to `AppLifecycleState.resumed` / `paused` to toggle RTDB presence. Registered in `HomeBloc`.

---

## Data Models

### `HomeState` (BLoC state — not persisted)
```
partner:       User
couple:        Couple
partnerMood:   Mood?          // null until first RTDB event
isOnline:      bool
recentMoods:   List<Mood>
```

### `Couple` (domain entity — from roadmap)
```
id:            String
userAId:       String
userBId:       String
pairedAt:      DateTime
streakDays:    int
totalMoments:  int
```

### `Mood` (domain entity — full definition in mood.md)
```
id:            MoodType       // enum
label:         String
emoji:         String
sentAt:        DateTime
userId:        String
```

---

## BLoC: `HomeBloc`

**Provided at:** `HomeScreen` subtree. Lives as long as the home tab is active. RTDB subscriptions are cancelled in `close()`.

### Events
```
HomeStarted
PartnerPresenceUpdated  { isOnline: bool }
PartnerMoodUpdated      { mood: Mood }
FloatingReactionBurst   // internal — fired after mood update for visual burst
RecentMoodsRefreshed    { moods: List<Mood> }
```

### States
```
HomeLoading
HomeLoaded {
  partner:      User
  couple:       Couple
  partnerMood:  Mood?
  isOnline:     bool
  recentMoods:  List<Mood>
}
HomeError { message: String }
```

### Internal stream subscriptions (held in bloc)
```
StreamSubscription _presenceSub   // RTDB onValue
StreamSubscription _moodSub       // RTDB onValue
```

Both are cancelled in `close()` override.

### Handler: `HomeStarted`
1. Emit `HomeLoading`
2. Fetch own `User` + `Couple` from repositories (single fetch)
3. Load `recentMoods` from Firestore (limit 10)
4. Subscribe to RTDB presence stream → dispatch `PartnerPresenceUpdated` on each event
5. Subscribe to RTDB mood stream → dispatch `PartnerMoodUpdated` on each event
6. Emit `HomeLoaded` with all loaded data

---

## Shared Widgets Used

| Widget | Location on screen |
|---|---|
| `MeshGradientPainter` | Full-screen background CustomPainter |
| `ConicOrbPainter` | PartnerOrbSection — spinning ring |
| `PulseRings` | PartnerOrbSection — 3 expanding rings |
| `HeartbeatVisualizer` | Below orb section |
| `GlassCard` | QuickAction pills, MoodChip |
| `MoodChip` | MoodStrip horizontal scroll items |
| `GradientText` | Not used directly on home (partner name is plain white) |
| `LiveIndicator` | Online badge inside PartnerOrb |
| `LoadingDots` | HomeLoading state placeholder |
| `UsyncBottomNav` | Persistent footer (provided by shell route) |
| `ParticleField` | Not on home (reserved for auth/pairing screens) |
