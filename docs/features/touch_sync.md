# Feature: Touch Sync

A minimal, full-screen experience where holding the fingerprint icon transmits a live touch signal to the partner. The partner's device receives the signal and responds with haptic feedback. Designed to simulate physical presence across distance.

---

## Screens

### TouchSyncScreen (`/touch-sync`)

Not a bottom-nav tab. Accessed via the Quick Actions row on HomeScreen (👆 Touch pill).

**Layout (full screen, centred):**
1. Dark mesh gradient background
2. Large ambient radial cyan glow blob (700 px, blurred, centre)
3. Header row (floating, top):
   - `NeonBackButton`
   - "Touch Sync" title
4. `TouchArea` widget (vertical centrepiece):
   - `PulseRings` (3 expanding cyan rings, continuous)
   - Fingerprint emoji `🫰` (90 px, centred above rings)
5. Text block (below touch area):
   - "Hold to sync" title
   - Subtitle: "Press and hold the icon. Aria will feel your touch across the distance."
   - `LiveIndicator` — "Connected · 0ms latency" with cyan dot
6. No bottom nav (full-screen experience)

**Fingerprint interaction states:**
- **Idle:** `🫰`, `drop-shadow(0 0 25px rgba(0,212,255,.65))`, `breathe` animation
- **Active (holding):** glow intensifies to `drop-shadow(0 0 60px rgba(0,212,255,1))`, scale 1.2, rings pulse faster
- **Partner touching:** additional concentric ring burst from centre

---

### TouchArea (widget)

`GestureDetector` wrapping a `Stack`:
- `PulseRings` layer (200 / 260 / 320 px, cyan, continuous 3 s cycle)
- Centre fingerprint — `AnimatedContainer` for glow/scale transitions
- When `TouchSyncState.isPartnerTouching == true`: a second set of rings (orange-pink tint) overlaid on top to visually distinguish partner's signal

---

## User Flows

### Initiating a Touch
```
TouchSyncScreen mounts
  → TouchSyncBloc.ScreenMounted
  → RTDB stream subscription begins for partner touch state
  → LiveIndicator shows connection status

User long-presses fingerprint icon
  → GestureDetector.onLongPressStart
  → TouchSyncBloc.TouchPressed
  → ITouchRepository.setTouchActive(coupleId, uid, true) → RTDB write
  → HapticFeedback.heavyImpact() (own device — confirmation)
  → UI: glow intensifies, rings pulse faster
  → CanvasState.isActive = true

User releases
  → GestureDetector.onLongPressEnd
  → TouchSyncBloc.TouchReleased
  → ITouchRepository.setTouchActive(coupleId, uid, false) → RTDB write
  → HapticFeedback.lightImpact() (own device — release confirmation)
  → UI returns to idle state
```

### Partner Touching (receiving end)
```
RTDB /touch/{coupleId}/{partnerUid}/isActive → true
  → ITouchRepository stream emits true
  → TouchSyncBloc.RemoteTouchReceived(isActive: true)
  → TouchSyncState.isPartnerTouching = true
  → UI: partner ring burst overlaid
  → HapticFeedback pattern played:
      heavyImpact → 80 ms → mediumImpact → 80 ms → lightImpact
      (simulates a warm touch landing)
  → Continue repeating haptic every 1.2 s while isActive remains true
      (uses Timer.periodic cancelled on RemoteTouchReceived(false))

Partner releases
  → RTDB flips to false
  → TouchSyncBloc.RemoteTouchReceived(isActive: false)
  → TouchSyncState.isPartnerTouching = false
  → Haptic timer cancelled
  → Partner ring burst fades out
```

### Simultaneous Touch
```
Both partners hold simultaneously
  → Both RTDB nodes set to true
  → Each device shows own active state + partner active state
  → Visual: both ring sets pulsing together
  → Haptic: alternating patterns to avoid identical vibrations
      own device:     HapticFeedback.heavyImpact
      partner signal: custom Vibration.vibrate([0, 100, 50, 100]) pattern
```

### Connection Lost
```
RTDB stream emits connection error or null
  → TouchSyncBloc.ConnectionLost
  → LiveIndicator switches to "Reconnecting…" with grey dot
  → All active states cleared
  → Auto-reconnect via RTDB SDK (no manual retry needed)
  → On reconnect → TouchSyncBloc.ConnectionRestored
```

### Screen Dismissed
```
NeonBackButton tapped OR back gesture
  → If own touch is active → TouchSyncBloc.TouchReleased (cleanup)
  → ITouchRepository.setTouchActive(coupleId, uid, false)
  → RTDB subscription cancelled
  → GoRouter.pop()
```

---

## API Requirements

### Firebase RTDB — Touch state

Single-node write strategy: the touch node is always overwritten, never appended. This avoids unbounded list growth and provides instant read for any new subscriber.

| Path | Type | Operation | Trigger |
|---|---|---|---|
| `/touch/{coupleId}/{uid}/isActive` | `bool` | `set(true)` | `TouchPressed` |
| `/touch/{coupleId}/{uid}/isActive` | `bool` | `set(false)` | `TouchReleased` / screen dispose |
| `/touch/{coupleId}/{uid}/timestamp` | `int` (epoch ms) | `set(now)` | Each `TouchPressed` |
| `/touch/{coupleId}/{partnerUid}/isActive` | `bool` | `onValue` stream | Screen mounted |

**RTDB `onDisconnect` hook:**
On screen mount, register `onDisconnect().set(false)` for the own-user touch node. This ensures the touch state clears automatically if the app crashes or loses connection while the user was holding.

### Haptic (local — no network)
| Package | Usage |
|---|---|
| `vibration` (pub.dev) | Custom amplitude + pattern vibration for partner touch signal |
| `HapticFeedback` (Flutter SDK) | Own-device confirmation taps |

---

## Data Models

### `TouchEvent` (domain entity)
```
coupleId:   String
userId:     String
isActive:   bool
timestamp:  DateTime
```

Not persisted to Firestore. RTDB only — ephemeral state.

### `TouchSyncState` (BLoC state — not persisted)
```
isOwnerTouching:   bool     // own press held
isPartnerTouching: bool     // partner's RTDB node is true
isConnected:       bool     // RTDB connection healthy
latencyMs:         int      // RTDB connection ping (from .info/connected)
```

---

## BLoC: `TouchSyncBloc`

**Provided at:** `TouchSyncScreen` subtree. All subscriptions and timers cancelled on `close()`.

### Events
```
ScreenMounted
TouchPressed
TouchReleased
RemoteTouchReceived    { isActive: bool }
ConnectionLost
ConnectionRestored
```

### States
```
TouchSyncInitial
TouchSyncConnecting
TouchSyncReady {
  isOwnerTouching:   bool
  isPartnerTouching: bool
  isConnected:       bool
  latencyMs:         int
}
```

### Internal handles (held in bloc)
```
StreamSubscription _partnerTouchSub   // RTDB onValue
Timer?             _hapticTimer        // periodic haptic while partner is touching
```

### Handler: `ScreenMounted`
1. Emit `TouchSyncConnecting`
2. Register RTDB `onDisconnect` for own touch node
3. Subscribe to partner touch stream
4. Emit `TouchSyncReady(isOwnerTouching: false, isPartnerTouching: false, isConnected: true, latencyMs: 0)`

### Handler: `TouchPressed`
1. Write `isActive: true` to RTDB
2. `HapticFeedback.heavyImpact()`
3. Emit updated state with `isOwnerTouching: true`

### Handler: `TouchReleased`
1. Write `isActive: false` to RTDB
2. `HapticFeedback.lightImpact()`
3. Emit updated state with `isOwnerTouching: false`

### Handler: `RemoteTouchReceived(isActive: true)`
1. Emit state with `isPartnerTouching: true`
2. Start `_hapticTimer` — fires every 1.2 s, plays vibration pattern
3. Fire initial haptic sequence immediately

### Handler: `RemoteTouchReceived(isActive: false)`
1. Cancel and null `_hapticTimer`
2. Emit state with `isPartnerTouching: false`

---

## Shared Widgets Used

| Widget | Usage |
|---|---|
| `PulseRings` | Continuous background rings (cyan) + partner-active overlay rings |
| `NeonBackButton` | Header back navigation |
| `LiveIndicator` | Connection status row below text block |
| `MeshGradientPainter` | Background gradient |
