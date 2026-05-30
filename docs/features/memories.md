# Feature: Memories

The couple's shared emotional archive. Every saved canvas drawing, significant touch moment, or mood milestone appears here as a Memory card. The space is intimate and nostalgic — glass cards with glowing borders, cinematic full-screen detail view.

---

## Screens

### MemorySpaceScreen (`/memories`)

Bottom-nav tab (🫧 Memories). Scrollable list of memory cards.

**Layout:**
1. Mesh gradient background
2. Header (non-scrolling):
   - "Memory Space" title
   - "Your shared emotional archive" subtitle (muted)
3. `ListView` of `MemoryCard` widgets (scrollable, no bottom-nav overlap — `padding.bottom = 100`)
4. Empty state shown when list is empty (see Empty State section)
5. `UsyncBottomNav`

**Sort order:** Most recent first (`createdAt` descending).

**Grouped headers (v1.1 scope):** Cards may eventually be grouped by month ("May 2026"), but v1 uses a flat list.

---

### MemoryCard (widget)

Glass rounded card with:
- **Thumbnail area** (160 px tall): gradient background per memory type + centred emoji (72 px). If `thumbnailUrl` is available (canvas saves), shows `CachedNetworkImage` with a fade-in + glass overlay.
- **Footer row**: left side (title 14 px bold, date 12 px muted) + right side (`MemoryTag` chip)
- Tap → navigates to `MemoryDetailScreen` with the `Memory` entity passed via GoRouter `extra`

**Gradient per memory type:**
| Type | Gradient |
|---|---|
| canvas | `rgba(255,45,120,.15) → rgba(155,78,221,.15)` |
| touch | `rgba(0,212,255,.10) → rgba(155,78,221,.15)` |
| mood | `rgba(255,215,0,.08) → rgba(255,45,120,.12)` |
| milestone | `rgba(0,212,255,.08) → rgba(11,78,221,.15)` |

---

### MemoryTag (widget)

Small pill chip showing memory type label with a type-appropriate accent colour:
| Type | Background | Text colour |
|---|---|---|
| canvas | `rgba(255,110,199,.15)` | `#FF6EC7` |
| touch | `rgba(155,78,221,.15)` | `#C77DFF` |
| mood | `rgba(0,212,255,.12)` | `#00D4FF` |
| milestone | `rgba(255,215,0,.12)` | `#FFD700` |

---

### MemoryDetailScreen (`/memories/:id`)

Full-screen, cinematic view of a single memory. No bottom nav.

**Layers:**
1. Background: large blurred emoji/thumbnail (`ImageFiltered(imageFilter: blur(40, 40))`) at 12% opacity — creates a soft ambient backdrop
2. Foreground content (`Column`):
   - `NeonBackButton` (left) + ♡ favourite toggle button (right) in a `Row`, padding top 55 px
   - Flexible centre: large emoji (110 px) or `CachedNetworkImage` (full width), centred
   - **Footer** (fixed bottom, gradient overlay from bg1):
     - Memory title (26 px bold)
     - Date + type label (14 px muted)
     - 3-button action row: Share, Save, Favourite

**Favourite button:** heart icon ♡ / ♥. Toggles `Memory.isFavourited`. Active state has pink glow.

**Footer gradient:** `LinearGradient(from bg1 at 100% opacity → transparent at 0%)`, positioned over the bottom 200 px.

---

### Empty State (inline within MemorySpaceScreen)

Shown when `MemoryState.memories.isEmpty`.

**Visual:**
- Two dashed rotating arcs (160 / 210 px, `opacity: 0.06`)
- Centre breathing orb (120 px dashed border) with 🫧 emoji (50 px)
- "No memories yet." title (26 px)
- Descriptive text (15 px muted, max-width 280 px)
- `GlowButton` "Create your first moment ✦" → navigate to `/canvas`
- `OutlineButton` "Maybe later"

---

## User Flows

### Browsing Memories
```
User taps Memories tab in BottomNav
  → MemoryBloc.MemoriesLoaded dispatched
  → Firestore query: /memories/{coupleId}/items, orderBy createdAt desc
  → MemoryLoaded state → ListView renders MemoryCard list
  → If empty → EmptyState widget shown
```

### Opening Memory Detail
```
User taps MemoryCard
  → GoRouter.push('/memories/:id', extra: memory)
  → MemoryDetailScreen receives Memory entity via GoRouter extra
  → No additional API call needed (full entity already loaded)
  → Large art rendered, footer shown
```

### Favouriting a Memory
```
MemoryDetailScreen → ♡ tapped
  → MemoryBloc.MemoryFavourited(memoryId, true/false)
  → Firestore /memories/{coupleId}/items/{id} → update({isFavourited: !current})
  → Optimistic update: state updates immediately, reverts on failure
  → Heart icon animates: scale pulse on favourite
```

### Sharing a Memory
```
"Share" action button tapped
  → Share.shareFiles([imageFile]) (using `share_plus` package)
  → If no thumbnailUrl → Share.shareText(title + date)
```

### Saving (downloading) a Memory
```
"Save" action button tapped
  → If thumbnailUrl exists: download bytes → save to device gallery (using `image_gallery_saver`)
  → If no image (mood/touch memory): share as text
  → Success snackbar: "Saved to photos"
```

### Memory Created from Canvas (cross-feature)
```
CanvasBloc.MemorySaved succeeds
  → IMemoryRepository.saveMemory(Memory(type: canvas, ...))
  → Firestore write to /memories/{coupleId}/items
  → If MemoryBloc is active (mounted), Firestore snapshot updates the list
  → New card appears at top of MemorySpaceScreen
```

### Memory Created from Milestone (automated)
```
Cloud Function detects streak milestone or moment count threshold
  → Writes Memory(type: milestone) to Firestore
  → FCM notification sent to both partners
  → MemoryBloc refreshes list on next mount
```

---

## API Requirements

### Firestore — Memory storage

| Collection | Operation | Description |
|---|---|---|
| `/memories/{coupleId}/items` | `add(MemoryModel)` | Create memory (canvas, mood, touch) |
| `/memories/{coupleId}/items` | `orderBy('createdAt', desc).get()` | Load all memories |
| `/memories/{coupleId}/items` | `snapshots()` stream | Real-time updates (new memories added by partner) |
| `/memories/{coupleId}/items/{id}` | `update({isFavourited: bool})` | Toggle favourite |
| `/memories/{coupleId}/items/{id}` | `delete()` | Delete memory |

### Firebase Storage — Canvas thumbnails

| Operation | Path |
|---|---|
| `getDownloadURL` | `/canvas-memories/{coupleId}/{timestamp}.png` |

Already uploaded by `CanvasRepository.saveCanvasBitmap`. `MemoryRepository` only stores the URL.

### Firebase Cloud Functions

| Trigger | Memory type created |
|---|---|
| `Firestore /couples/{id}` streakDays reaches 7, 30, 100 | `milestone` |
| `Firestore /memories/{coupleId}/items` count reaches 100 | `milestone` |

### External packages
| Package | Purpose |
|---|---|
| `share_plus` | Share memory as image/text |
| `image_gallery_saver` | Save image to device gallery |
| `cached_network_image` | Thumbnail loading with cache |

---

## Data Models

### `Memory` (domain entity)
```
id:              String
coupleId:        String
type:            MemoryType       // enum: canvas, touch, mood, milestone
thumbnailUrl:    String?          // Firebase Storage URL, null for non-canvas
thumbnailEmoji:  String           // fallback emoji for all types
title:           String
createdAt:       DateTime
isFavourited:    bool
createdByUserId: String
```

### `MemoryType` enum
```dart
enum MemoryType { canvas, touch, mood, milestone }
```

Extension on `MemoryType` provides `defaultEmoji`, `tagLabel`, `tagColor`, `thumbnailGradient`.

### `MemoryModel` (data layer — Firestore)
```json
{
  "id":              "mem_abc123",
  "coupleId":        "couple_xyz",
  "type":            "canvas",
  "thumbnailUrl":    "https://storage.googleapis.com/...",
  "thumbnailEmoji":  "🌸",
  "title":           "Our first doodle",
  "createdAt":       "2026-05-28T10:00:00Z",
  "isFavourited":    false,
  "createdByUserId": "uid_abc"
}
```

---

## BLoC: `MemoryBloc`

**Provided at:** `MemorySpaceScreen` subtree. Firestore snapshot stream active while screen is mounted.

### Events
```
MemoriesLoaded
MemorySelected       { id: String }    // navigation only — no state change
MemoryFavourited     { id: String, isFavourited: bool }
MemoryDeleted        { id: String }
MemoriesUpdated      { memories: List<Memory> }   // from Firestore stream
```

### States
```
MemoryInitial
MemoryLoading
MemoryLoaded {
  memories:       List<Memory>
  selectedMemory: Memory?      // for detail view pre-load
}
MemoryEmpty
MemoryError { message: String }
```

### Handler: `MemoriesLoaded`
1. Emit `MemoryLoading`
2. Subscribe to Firestore `snapshots()` stream
3. Each emission → dispatch `MemoriesUpdated(memories)`
4. Initial emission → if empty → emit `MemoryEmpty`; else → emit `MemoryLoaded`

### Handler: `MemoriesUpdated`
- Emit `MemoryLoaded(memories)` or `MemoryEmpty` based on list length

### Handler: `MemoryFavourited(id, isFavourited)`
1. Optimistic: emit state with toggled memory in list
2. Call `IMemoryRepository.toggleFavourite(id, isFavourited)`
3. On failure: revert optimistic update, emit error

### Handler: `MemoryDeleted(id)`
1. Optimistic: remove from list, emit updated state
2. Call `IMemoryRepository.deleteMemory(id)`
3. On failure: restore item

---

## Shared Widgets Used

| Widget | Usage |
|---|---|
| `GlassCard` | MemoryCard base + MemoryDetailScreen overlay |
| `NeonBackButton` | MemoryDetailScreen header |
| `GlowButton` | Empty state CTA |
| `OutlineButton` | Empty state secondary action |
| `MemoryTag` | Memory type chip (shared/widgets/) |
| `LoadingDots` | Loading state placeholder |
| `UsyncBottomNav` | Persistent footer on MemorySpaceScreen |
| `MeshGradientPainter` | Background |
