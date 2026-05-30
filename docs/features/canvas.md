# Feature: Canvas

A shared, real-time collaborative drawing screen. Both partners see each other's strokes appear live. The canvas persists within the session; completed drawings can be saved as Memory items.

---

## Screens

### CanvasScreen (`/canvas`)

**Layout:**
1. Transparent gradient background (bg1 → bg2, very subtle — the drawing surface reads as dark)
2. `DrawingCanvas` — full-screen `CustomPaint` + `GestureDetector`
3. **Header** (floating, gradient fade from top, z-indexed above canvas)
   - `NeonBackButton`
   - Title "Shared Canvas"
   - Partner live indicator (dot + "Aria is here")
4. **Floating toolbar** — centred, positioned 100 px above bottom nav, glass pill
5. **UsyncBottomNav** — visible (canvas is a primary tab destination)

The header and toolbar use `Stack` positioning so the canvas occupies the full screen beneath them.

---

### DrawingCanvas (widget)

**Rendering:**
- `CustomPaint` with a `CanvasStrokePainter` that draws the full list of `CanvasStroke` objects from `CanvasState.strokes`
- Each stroke is drawn with `Paint`
  - `color`: stroke colour
  - `strokeWidth`: 3.0 (pen) or 30.0 (eraser, `BlendMode.clear` on a `saveLayer`)
  - `maskFilter`: `MaskFilter.blur(BlurStyle.solid, 4)` — the glow effect
  - `strokeCap` / `strokeJoin`: `StrokeCap.round`, `StrokeJoin.round`
- Partner strokes are rendered identically but sourced from `CanvasState.remoteStrokes` — no visual distinction (intentional: feels like one shared hand)

**Gesture handling:**
- `GestureDetector.onPanStart` → `CanvasBloc.StrokeStarted(offset)`
- `GestureDetector.onPanUpdate` → `CanvasBloc.StrokeUpdated(offset)`
- `GestureDetector.onPanEnd` → `CanvasBloc.StrokeEnded`
- Touch and mouse both handled (`HitTestBehavior.opaque`)

**Erase strategy:**
- Eraser does not use `BlendMode.clear` on individual points (fragile with `CustomPaint`)
- Instead, eraser strokes are recorded as regular strokes with `isEraser: true`
- `CanvasStrokePainter` draws eraser strokes last in each batch, using `BlendMode.dstOut` on a `saveLayer` wrapping all strokes

---

### CanvasToolbar (widget)

Floating glass pill with `Row` of controls:

| Position | Control | Action |
|---|---|---|
| 1 | ✏️ Glow Pen | `setTool(pen)` — active state: pink tint |
| 2 | 🧹 Eraser | `setTool(eraser)` |
| — | Divider | 1 px vertical line |
| 3–7 | 5 colour dots | `setColor(hex)` — selected: scale 1.25 + white border |
| — | Divider | 1 px vertical line |
| 8 | 🗑️ Clear | `CanvasBloc.CanvasCleared` + confirmation (if strokes exist) |
| 9 | 💾 Save Memory | `CanvasBloc.MemorySaved` |

Colour options: `#FF6EC7` (pink), `#C77DFF` (lavender), `#00D4FF` (cyan), `#FFFFFF` (white), `#FFD700` (gold).

---

## User Flows

### Drawing (own strokes)
```
User places finger on canvas
  → GestureDetector.onPanStart
  → CanvasBloc.StrokeStarted(Offset(x, y))
  → new CanvasStroke created locally with id, color, tool, userId
  → State: activeStroke added to strokes list
  → CustomPaint repaints

User drags
  → CanvasBloc.StrokeUpdated(Offset(x, y))
  → offset appended to activeStroke.points
  → simultaneously: ICanvasRepository.pushStrokePoint(coupleId, strokeId, point) → RTDB

User lifts finger
  → CanvasBloc.StrokeEnded
  → activeStroke finalised, moved from active to committed strokes
  → RTDB stroke marked complete
```

### Receiving partner strokes
```
RTDB /canvas/{coupleId}/strokes stream emits new point
  → ICanvasRepository emits CanvasStroke event (filtered: excludeUserId = own uid)
  → CanvasBloc.RemoteStrokeReceived(stroke)
  → remote stroke appended to CanvasState.remoteStrokes
  → CustomPaint repaints
```

### Changing colour
```
Colour dot tapped
  → CanvasBloc.ColorChanged(color)
  → CanvasState.activeColor updates
  → Toolbar dot shows selected state
  → tool automatically switches back to pen if eraser was active
```

### Clearing canvas
```
🗑️ tapped
  → if CanvasState.strokes.isEmpty → no-op
  → else: show confirmation `AlertDialog`
  → confirmed → CanvasBloc.CanvasCleared
    → CanvasState.strokes = [], remoteStrokes = []
    → ICanvasRepository.clearCanvas(coupleId) → deletes RTDB node
    → partner receives deletion event, their canvas also clears
```

### Saving as Memory
```
💾 tapped
  → CanvasBloc.MemorySaved
  → CanvasState.isSaving = true (toolbar shows LoadingDots)
  → canvas rendered to Uint8List via RepaintBoundary + RenderRepaintBoundary.toImage()
  → ICanvasRepository.saveCanvasBitmap(coupleId, bytes) → uploads to Firebase Storage
  → returns downloadUrl
  → IMemoryRepository.saveMemory(Memory(type: canvas, thumbnailUrl: downloadUrl, title: "Canvas", ...))
  → CanvasState.isSaving = false
  → success snackbar: "Saved to memories 💾"
```

---

## API Requirements

### Firebase RTDB — Realtime stroke sync

| Path | Operation | Trigger |
|---|---|---|
| `/canvas/{coupleId}/strokes/{strokeId}/points` | `push` (append) | Each `onPanUpdate` event |
| `/canvas/{coupleId}/strokes/{strokeId}/meta` | `set` | `StrokeStarted` (color, tool, userId, timestamp) |
| `/canvas/{coupleId}/strokes/{strokeId}/complete` | `set(true)` | `StrokeEnded` |
| `/canvas/{coupleId}/strokes` | `onChildAdded` stream | Partner stroke detection |
| `/canvas/{coupleId}` | `remove` | `CanvasCleared` |

**RTDB write throttle:** Points are batched — write every 16 ms (one animation frame), not on every `onPanUpdate` callback (which can fire at 120 Hz). Use a `Timer.periodic(16ms)` buffer that flushes accumulated points in a single `update()` call.

### Firebase Storage
| Operation | Path | Trigger |
|---|---|---|
| `putData(bytes)` | `/canvas-memories/{coupleId}/{timestamp}.png` | `MemorySaved` |
| `getDownloadURL` | same path | After upload success |

### Firestore
Saving a memory delegates to `IMemoryRepository.saveMemory` — see `memories.md`.

---

## Data Models

### `CanvasStroke` (domain entity)
```
id:          String          // UUID, generated on StrokeStarted
coupleId:    String
userId:      String
points:      List<Offset>    // grows during drawing
color:       Color
width:       double           // 3.0 pen, 30.0 eraser
isEraser:    bool
isComplete:  bool            // false during active drawing
timestamp:   DateTime
```

### `CanvasStrokeModel` (data layer — RTDB serialisation)
`Offset` serialised as `{x: double, y: double}`. Full point list stored as array of maps.

```json
{
  "id":         "stroke_abc",
  "userId":     "uid_xyz",
  "color":      "0xFFFF6EC7",
  "width":      3.0,
  "isEraser":   false,
  "isComplete": false,
  "timestamp":  1748563200000,
  "points": [
    { "x": 120.5, "y": 340.2 },
    { "x": 121.0, "y": 341.8 }
  ]
}
```

Color serialised as integer (`Color.value`) to avoid string parsing overhead on high-frequency writes.

---

## BLoC: `CanvasBloc`

**Provided at:** `CanvasScreen` subtree. RTDB subscription starts on mount, cancelled on dispose.

### Events
```
CanvasMounted
StrokeStarted         { offset: Offset }
StrokeUpdated         { offset: Offset }
StrokeEnded
ColorChanged          { color: Color }
ToolChanged           { tool: CanvasTool }    // enum: pen, eraser
CanvasCleared
MemorySaved
RemoteStrokeReceived  { stroke: CanvasStroke }
RemoteCanvasCleared
```

### States
```
CanvasState {
  strokes:       List<CanvasStroke>    // own committed strokes
  activeStroke:  CanvasStroke?         // stroke being drawn right now
  remoteStrokes: List<CanvasStroke>    // partner strokes
  activeColor:   Color                 // default: #FF6EC7
  activeTool:    CanvasTool            // default: pen
  isSaving:      bool
}
```

### Key handler details

**`StrokeStarted`:**
- Create new `CanvasStroke` with `id = uuid()`, initial `points: [offset]`
- Set `CanvasState.activeStroke = stroke`
- Write stroke meta to RTDB

**`StrokeUpdated`:**
- Append offset to `activeStroke.points`
- Enqueue point for RTDB batch write (16 ms flush timer)

**`StrokeEnded`:**
- Move `activeStroke` → `strokes` list
- Set `activeStroke = null`
- Mark RTDB stroke as `complete: true`

**`RemoteStrokeReceived`:**
- If stroke with same `id` exists in `remoteStrokes` → update its points
- Else → append new stroke

**`CanvasCleared`:**
- Clear both `strokes` and `remoteStrokes`
- Write RTDB delete

---

## Shared Widgets Used

| Widget | Usage |
|---|---|
| `GlassCard` | Toolbar container (glass pill shape) |
| `NeonBackButton` | Header back navigation |
| `LiveIndicator` | Header — "Aria is here" with cyan live dot |
| `LoadingDots` | Toolbar save button loading state |
| `UsyncBottomNav` | Persistent footer |
| `CanvasStrokePainter` | Core drawing — custom painter (canvas/painters/) |
