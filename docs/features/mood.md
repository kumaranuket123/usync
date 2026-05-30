# Feature: Mood Sharing

Allows a user to express their current emotional state with a single tap. The selected mood is transmitted to the partner in real time, appearing on their Home screen and in the notification feed. Moods are also stored in history for the MoodStrip on HomeScreen.

---

## Screens

### MoodScreen (`/mood`)

Not a bottom-nav tab. Accessed via the Quick Actions row on HomeScreen (💭 Mood pill). Full-screen experience — no bottom nav.

**Layout:**
1. Mesh gradient background
2. Header (non-floating, part of the column):
   - `NeonBackButton` (left)
   - "How are you feeling?" title
   - "Your partner will feel this" subtitle (muted)
3. Mood bubble grid — `Wrap` of 6 `MoodBubble` widgets (see below)
4. `GlowButton` "Send My Mood ✦" — fixed at the bottom, above safe area

---

### MoodBubble (widget)

Rounded rectangle glass card (110 px min-width), containing:
- Emoji (38 px)
- Label text (12 px, muted → white on selected)

**Animation:** `TweenAnimationBuilder` driving `translateY: 0 → -8` on a looping curve (`Curves.easeInOut`). Each bubble has a unique `Duration` (3.2 s, 4.0 s, 3.6 s, 4.4 s, 3.8 s, 4.2 s) and staggered `delay` (0 / 0.4 / 0.8 / 0.2 / 0.6 / 1.0 s) to prevent synchronised motion.

**Selected state:**
- `transform: scale(1.12)` (via `AnimatedScale`)
- `background: primary.withOpacity(0.15)`
- `border: primary.withOpacity(0.4)`
- `boxShadow: primaryGlow` (from `UsyncThemeData`)
- Immediate: no animation delay for selection response

**6 moods:**
| Enum | Emoji | Label |
|---|---|---|
| `MoodType.happy` | 😊 | Happy |
| `MoodType.thinkingAboutYou` | 💭 | Thinking About You |
| `MoodType.missingYou` | 💖 | Missing You |
| `MoodType.sleeping` | 😴 | Sleeping |
| `MoodType.relaxing` | 🌸 | Relaxing |
| `MoodType.busy` | ⚡ | Busy |

---

## User Flows

### Selecting and Sending a Mood
```
MoodScreen opens
  → MoodBloc.ScreenOpened
  → MoodState initialised: selectedMood = null (or last sent mood pre-selected)

User taps a MoodBubble
  → MoodBloc.MoodSelected(MoodType.happy)
  → MoodState.selectedMood = happy
  → Bubble scales up with glow
  → Previously selected bubble returns to idle

User taps "Send My Mood ✦"
  → MoodBloc.MoodSent
  → If selectedMood == null → show inline hint "Pick a mood first"
  → MoodState.isSending = true → button shows LoadingDots
  → IMoodRepository.sendMood(coupleId, uid, selectedMood)
      → writes to RTDB /mood/{coupleId}/{uid}/current
      → writes to Firestore /moods/{coupleId}/history (for strip + notifications)
  → FCM notification sent to partner (via Cloud Function trigger on Firestore write)
  → MoodState.isSending = false
  → success: GoRouter.pop() back to HomeScreen
  → HomeBloc receives MoodStrip refresh
```

### Partner Receives Mood (on HomeScreen)
```
RTDB /mood/{coupleId}/{partnerUid}/current fires onValue
  → HomeBloc.PartnerMoodUpdated(mood)
  → HomeState.partnerMood = mood
  → Partner mood text updates with a crossfade transition
  → MoodStrip adds new chip at left
  → FloatingReactionBurst dispatched (burst of themed emoji)
```

### Partner Receives Notification (push — background)
```
Cloud Function triggers on Firestore /moods/{coupleId}/history write
  → sends FCM to partner device token
  → notification body: "Aria's mood changed to "Thinking About You" 💭"
  → tapping notification → deep-link to /home (not mood screen)
```

### Re-opening Mood Screen
```
MoodScreen opened again
  → IMoodRepository.getLastSentMood(uid) → returns Mood? from Firestore
  → If not null → MoodState.selectedMood = lastMood (pre-selected)
  → User can confirm same mood or pick different
```

---

## API Requirements

### Firebase RTDB — Current mood (live sync to partner HomeScreen)

| Path | Type | Operation | Trigger |
|---|---|---|---|
| `/mood/{coupleId}/{uid}/current` | `MoodModel JSON` | `set` | `MoodSent` |
| `/mood/{coupleId}/{partnerUid}/current` | `MoodModel JSON` | `onValue` stream | HomeBloc mounted |

### Firestore — Mood history (persistence + notification trigger)

| Collection | Document | Operation | Purpose |
|---|---|---|---|
| `/moods/{coupleId}/history` | auto-ID | `add(MoodModel)` | Persist mood, trigger Cloud Function |
| `/moods/{coupleId}/history` | — | `query(limit: 10, orderBy: sentAt desc)` | HomeScreen MoodStrip |
| `/moods/{coupleId}/history` | — | `query(where userId == uid, limit: 1, orderBy: sentAt desc)` | Pre-select last mood |

### Firebase Cloud Functions (backend)

| Trigger | Action |
|---|---|
| `Firestore onCreate /moods/{coupleId}/history/{id}` | Read partner FCM token from `/users/{partnerId}` → send FCM notification |

**Note:** FCM device tokens are stored in Firestore `/users/{uid}/fcmToken` and updated on each app launch via `FirebaseMessaging.getToken()`.

---

## Data Models

### `Mood` (domain entity)
```
type:     MoodType     // enum (defined below)
label:    String       // display label
emoji:    String
userId:   String
sentAt:   DateTime
```

### `MoodType` enum
```dart
enum MoodType {
  happy,
  thinkingAboutYou,
  missingYou,
  sleeping,
  relaxing,
  busy;

  String get label => switch (this) {
    happy             => 'Happy',
    thinkingAboutYou  => 'Thinking About You',
    missingYou        => 'Missing You',
    sleeping          => 'Sleeping',
    relaxing          => 'Relaxing',
    busy              => 'Busy',
  };

  String get emoji => switch (this) {
    happy             => '😊',
    thinkingAboutYou  => '💭',
    missingYou        => '💖',
    sleeping          => '😴',
    relaxing          => '🌸',
    busy              => '⚡',
  };
}
```

### `MoodModel` (data layer — Firestore + RTDB serialisation)
```json
{
  "type":    "thinkingAboutYou",
  "label":   "Thinking About You",
  "emoji":   "💭",
  "userId":  "uid_abc",
  "sentAt":  "2026-05-30T21:00:00Z"
}
```

---

## BLoC: `MoodBloc`

**Provided at:** `MoodScreen` subtree.

### Events
```
ScreenOpened
MoodSelected     { type: MoodType }
MoodSent
```

### States
```
MoodInitial
MoodLoading           // loading last sent mood
MoodReady {
  selectedMood:  MoodType?
  lastSentMood:  Mood?
  isSending:     bool
}
MoodSentSuccess
MoodError { message: String }
```

### Handler: `ScreenOpened`
1. Emit `MoodLoading`
2. Fetch last sent mood from Firestore (see API)
3. Emit `MoodReady(selectedMood: lastSentMood?.type, isSending: false)`

### Handler: `MoodSelected(type)`
1. Emit `MoodReady(selectedMood: type)` — no async work, instant UI response

### Handler: `MoodSent`
1. Guard: `selectedMood == null` → emit `MoodError("Pick a mood first")`
2. Emit `MoodReady(..., isSending: true)`
3. `IMoodRepository.sendMood(coupleId, uid, selectedMood)`
4. Emit `MoodSentSuccess` — consumed by `BlocListener` for navigation

---

## Shared Widgets Used

| Widget | Usage |
|---|---|
| `MoodBubble` | 6 mood options (defined in shared/widgets/ — used here and in Widget Showcase) |
| `NeonBackButton` | Header back navigation |
| `GlowButton` | "Send My Mood ✦" CTA |
| `LoadingDots` | Button loading state during `isSending` |
| `MeshGradientPainter` | Background |
| `GlassCard` | Base of each `MoodBubble` |
