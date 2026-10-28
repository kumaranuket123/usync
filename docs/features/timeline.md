# Feature: Timeline

A cinematic vertical timeline visualising the couple's shared journey — connection date, first doodle, streak milestones, moment counts, and any custom events. Read-only in v1. The timeline is both a memory and a celebration of the relationship's growth over time.

---

## Screens

### TimelineScreen (`/timeline`)

Pushed from ProfileScreen ("Relationship Timeline" row). Not a bottom-nav destination.

**Layout:**
1. Mesh gradient background
2. Header row:
   - `NeonBackButton`
   - "Our Journey" title
   - "Anuket & Aria · [N] days" subtitle (muted) — day count computed from `couple.pairedAt`
3. Scrollable `Stack`:
   - **Gradient timeline line** — vertically positioned `Container` (1 px wide), left-aligned at 43 px from edge, `LinearGradient(pink → purple → cyan)`. Extends from top of first item to bottom of last.
   - **`ListView` of `TimelineItem` widgets** — padding left 24 px (line sits at 43 px, dots are 38 px, so line is behind dots)

**No bottom nav.**

---

### TimelineItem (widget)

A `Row` of:
- **`TimelineDot`** (38 px circle):
  - Background: `bg1` (dark, so the gradient line behind is hidden)
  - Border: 1.5 px, `rgba(255,45,120,.4)`
  - `BoxShadow`: `0 0 14px rgba(255,45,120,.3)`
  - Emoji inside (17 px)
  - Positioned `z-index: 2` (drawn after the line)
- **`TimelineCard`** (flexible width):
  - `GlassCard` with left margin 14 px
  - Event title (15 px bold white)
  - Note/description (13 px muted, 1.5 line height) — optional
  - Date (11 px, very muted)

**Dot emojis by milestone type:**
| MilestoneType | Emoji |
|---|---|
| `firstConnect` | 🎉 |
| `firstDoodle` | ✏️ |
| `streak7` | 🔥 |
| `streak30` | 🌙 |
| `streak100` | 💫 |
| `moments100` | 💖 |
| `custom` | ✨ |
| `today` (synthetic) | ✨ |

**Entrance animation:**
Each `TimelineItem` fades in and slides up from 20 px as the `ListView` scrolls them into view, using a `Visibility` + `AnimatedOpacity` combination with a staggered `Future.delayed` on mount. Delay = `index * 80ms`.

---

### "Today" Synthetic Item

The final item in the timeline is always the current day, regardless of whether a milestone occurred. It shows "Today · Day N" with the note "Still here. Still close. Still together." This item is assembled client-side — not stored in Firestore.

```dart
final todayItem = Milestone(
  id: 'today',
  type: MilestoneType.today,
  title: 'Today · Day ${daysSincePaired}',
  note: 'Still here. Still close. Still together.',
  occurredAt: DateTime.now(),
);
```

---

## User Flows

### Opening Timeline
```
ProfileScreen → "Relationship Timeline" tapped
  → GoRouter.push('/timeline')
  → TimelineBloc.TimelineLoaded dispatched
  → Firestore query: /milestones/{coupleId}/events, orderBy occurredAt asc
  → TimelineState.milestones populated
  → Synthetic "Today" item appended client-side
  → Items rendered with staggered entrance animation
```

### Viewing a Milestone Detail (v1.1 scope)
```
TimelineItem tapped (if it has an associated Memory)
  → navigate to MemoryDetailScreen for the linked memory
  → not all milestones have memories — tap only active if memory exists
```

### Auto-Created Milestones
Milestones are written by Firebase Cloud Functions. The client is read-only:

| Event | MilestoneType | Cloud Function trigger |
|---|---|---|
| Couple created | `firstConnect` | `couples.onCreate` |
| First canvas memory saved | `firstDoodle` | `memories.onCreate where type == canvas` |
| `couple.streakDays` reaches 7 | `streak7` | `couples.onUpdate where streakDays == 7` |
| `couple.streakDays` reaches 30 | `streak30` | same pattern |
| `couple.streakDays` reaches 100 | `streak100` | same pattern |
| `couple.totalMoments` reaches 100 | `moments100` | `couples.onUpdate where totalMoments == 100` |

All Cloud Function milestone writes also:
1. Push FCM notification to both partners
2. Write a `NotificationItem` to Firestore
3. Optionally write a `Memory(type: milestone)` for significant events

---

## API Requirements

### Firestore — Milestones

| Collection | Operation | Description |
|---|---|---|
| `/milestones/{coupleId}/events` | `orderBy('occurredAt', asc).get()` | Load full timeline |
| `/milestones/{coupleId}/events` | `add(MilestoneModel)` | Written by Cloud Functions only — client never writes |

### Couple data (for header day count)

| Collection | Operation | Description |
|---|---|---|
| `/couples/{coupleId}` | `get()` | Read `pairedAt` for day count calculation |

Already available in `HomeBloc` state — pass via GoRouter `extra` to avoid a duplicate Firestore fetch.

### No RTDB usage
Timeline is historical + static. No real-time sync required.

---

## Data Models

### `Milestone` (domain entity)
```
id:          String
coupleId:    String
type:        MilestoneType    // enum (see below)
title:       String           // e.g. "7-day streak achieved"
note:        String?          // descriptive sentence
occurredAt:  DateTime
linkedMemoryId: String?       // optional — links to a Memory for tap-through
```

### `MilestoneType` enum
```dart
enum MilestoneType {
  firstConnect,
  firstDoodle,
  streak7,
  streak30,
  streak100,
  moments100,
  custom,
  today,       // synthetic — never stored in Firestore
}
```

Extension on `MilestoneType` provides:
- `emoji` → String (dot icon)
- `defaultTitle` → String
- `defaultNote` → String?

### `MilestoneModel` (data layer — Firestore)
```json
{
  "id":              "ms_abc",
  "coupleId":        "couple_xyz",
  "type":            "streak7",
  "title":           "7-day streak achieved",
  "note":            "A week of daily connection. The first of many.",
  "occurredAt":      "2026-01-19T00:00:00Z",
  "linkedMemoryId":  null
}
```

---

## BLoC: `TimelineBloc`

**Provided at:** `TimelineScreen` subtree.

### Events
```
TimelineLoaded
```

### States
```
TimelineLoading
TimelineReady {
  milestones:      List<Milestone>    // includes synthetic "today" appended at tail
  daysSincePaired: int
}
TimelineEmpty {
  daysSincePaired: int
}
TimelineError { message: String }
```

### Handler: `TimelineLoaded`
1. Emit `TimelineLoading`
2. Read `couple.pairedAt` (from GoRouter `extra` or a fresh `ICoupleRepository.getCouple()`)
3. Compute `daysSincePaired = DateTime.now().difference(pairedAt).inDays`
4. Fetch milestones from Firestore (ordered asc)
5. Append synthetic `today` item
6. If milestones list (excluding today) is empty → emit `TimelineEmpty`
7. Else → emit `TimelineReady`

No stream subscription — timeline is loaded once and displayed statically. Pull-to-refresh is not needed in v1 (milestones are rare events).

---

## Shared Widgets Used

| Widget | Usage |
|---|---|
| `NeonBackButton` | Header back navigation |
| `GlassCard` | `TimelineCard` body |
| `MeshGradientPainter` | Background |
| `GradientText` | Not used directly (plain white for event titles) |
| `LoadingDots` | `TimelineLoading` state placeholder |

## Encryption and reminders (phase E4a)

Custom dates are sealed on the phone (title, note, emoji, day, yearly flag); the server holds only a placeholder. Reminders for them are local notifications at 9:00 scheduled by each phone, not pushes from the server. See "E4a" in [security.md](../security.md). Migration: `supabase/migrations/e2ee_timeline.sql`; `remove_milestone_reminders.sql` is applied later, at release.

