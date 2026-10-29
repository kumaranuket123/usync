# Feature: Onboarding

Covers the Splash screen and the five-slide onboarding carousel. These screens run only before a user is authenticated. After completion, the `onboardingSeen` flag is written to SharedPreferences so they are never shown again.

---

## Screens

### 1. SplashScreen (`/splash`)
App entry point. Shown for ~3 seconds on every launch regardless of auth state. The router decision (where to go next) is computed here.

**Visual layers (back to front):**
1. Dark 3-stop gradient background (`bg1 → bg2 → bg3`)
2. Large radial purple glow blob (centre, `filter:blur`)
3. `ParticleField` — 40 particles, all theme colours
4. Spinning conic-gradient orb (`ConicOrbPainter`, 130 px, 8 s rotation)
5. Three staggered `PulseRings` (0 s / 0.9 s / 1.8 s delay), pink, `wave` keyframe
6. Inner dark circle with 💫 emoji (100 px)
7. `GradientText` "USYNC" — 46 px, letter-spacing 10, 3-colour gradient
8. Subtitle "feel together" — 13 px, muted, letter-spacing 4

**Animations:**
- Whole logo assembly: `logo-in` (elastic scale-in, 1.3 s, `cubic-bezier(.34,1.56,.64,1)`)
- Orb: continuous rotation via `AnimationController(duration: 8s, repeat)`
- Rings: staggered `ScaleTransition` + `FadeTransition`

### 2. OnboardingScreen (`/onboarding`)
Five-slide `PageView` with a fixed footer overlay. Slides occupy the full screen; the footer (dots + skip + next button) sits above them at the bottom.

**Footer elements:**
- `TextButton` "Skip" (left) → navigates directly to `/login`
- Animated dots indicator (centre) — active dot expands width 7→26 px with pink glow
- Circular `GlowButton` "›" / "✓" (right, 62 px)

**Slide 5 — "Private\nby design."** Visual: `_PrivacyVisual` (a 🔒 in breathing rings). Text from `TrustCopy`, see [trust.md](trust.md).

**Slide 1 — "Feel close, even from far away."**
Visual: `ConnectedOrbsVisual`
- Two breathing orbs (90 px each), left=pink `radial-gradient`, right=purple `radial-gradient`
- Gradient connector line (150 px wide, 2 px tall) between them
- Both orbs animated with `breathe` (scale 1→1.07 with brightness), staggered 0.6 s

**Slide 2 — "Share emotions in realtime."**
Visual: `EmotionWaveVisual`
- Centre circle (100 px) with semi-transparent pink-purple gradient + 💖 emoji, `breathe` animation
- Three concentric `PulseRings` expanding outward (130 / 170 / 210 px), staggered 0.8 s each, `wave` keyframe (scale + opacity fade)

**Slide 3 — "Create moments together."**
Visual: `DoodleVisual`
- `CustomPainter` rendering two glow SVG paths (pink + purple) with a `feGaussianBlur`-equivalent `MaskFilter`
- Two glow circle dots on the path
- Static "drawing together…" muted text below

**Slide 4 — "Stay connected everywhere."**
Visual: `PresenceVisual`
- Three rotating dashed arcs (160 / 220 / 280 px) — outer two counter-rotate — via `AnimationController`
- Three coloured dots (pink / purple / cyan) at centre with staggered `breathe` (0 / 0.3 / 0.6 s delay)

---

## User Flows

### First Launch (new install)
```
App opens
  → SplashScreen shown
  → SplashBloc reads prefs: onboardingSeen = false
  → after 3 s → navigate to /onboarding
```

### Onboarding Navigation
```
OnboardingScreen (slide 0)
  → swipe left OR tap "›" → advance to slide 1
  → slide 1 → slide 2 → slide 3
  → on slide 3: "›" icon changes to "✓"
  → tap "✓" → write onboardingSeen = true to prefs
             → navigate to /login

  → tap "Skip" at any point → write onboardingSeen = true
                             → navigate to /login
```

### Returning User (onboarding already seen)
```
App opens
  → SplashScreen shown
  → SplashBloc reads prefs: onboardingSeen = true
  → reads Firebase Auth.currentUser
      → null   → navigate to /login
      → exists → fetch User entity
                  → coupleId null    → /pair-invite
                  → coupleId present → /home
```

### Swipe Gesture (PageView)
The `PageView` handles horizontal swipe natively. `OnboardingBloc` listens to `onPageChanged` callback and updates the active dot index. The next button always reflects the current page — it does not override swipe direction.

---

## API Requirements

### SharedPreferences (local only — no network calls)
| Key | Type | Description |
|---|---|---|
| `onboarding_seen` | `bool` | Written `true` on completion or skip |

### Firebase Auth (read-only during splash)
| Operation | Purpose |
|---|---|
| `FirebaseAuth.currentUser` | Determine post-splash route destination |

No writes occur during onboarding. Network calls begin only at auth screens.

---

## Data Models

No persistent data models. Onboarding state is purely ephemeral.

### `OnboardingPage` (UI model — not persisted)
```
index:       int
headline:    String
subtext:     String
visualType:  OnboardingVisualType  // enum: connectedOrbs, emotionWave, doodle, presence
```

Defined as a `const List<OnboardingPage>` in the BLoC or a constants file. Not serialised.

---

## BLoC / Cubit

### `SplashBloc`

**Provided at:** `SplashScreen` subtree only.

**Events:**
```
SplashStarted   // dispatched from initState
```

**States:**
```
SplashLoading
SplashNavigating { destination: SplashDestination }
```

```
enum SplashDestination {
  onboarding,
  login,
  pairInvite,
  home,
}
```

**Handler — `SplashStarted`:**
1. Wait for `AnimationController` completion signal (3 s minimum display)
2. Read `prefs.getBool('onboarding_seen')`
3. Read `FirebaseAuth.currentUser`
4. If `currentUser == null`:
   - `onboarding_seen == false` → emit `SplashNavigating(onboarding)`
   - `onboarding_seen == true`  → emit `SplashNavigating(login)`
5. If `currentUser != null`:
   - Fetch `User` from Firestore
   - `coupleId == null` → emit `SplashNavigating(pairInvite)`
   - `coupleId != null` → emit `SplashNavigating(home)`

---

### `OnboardingBloc`

**Provided at:** `OnboardingScreen` subtree only.

**Events:**
```
PageAdvanced      // next button tapped or swipe
PageChanged       { index: int }   // PageView.onPageChanged callback
OnboardingSkipped
OnboardingCompleted
```

**States:**
```
OnboardingState {
  currentPage: int          // 0–3
  isLastPage:  bool         // currentPage == 3
}
```

**Handler logic:**
- `PageAdvanced`: if `currentPage < 3` → emit `OnboardingState(currentPage + 1)`; else dispatch `OnboardingCompleted`
- `PageChanged(index)`: emit `OnboardingState(index)`
- `OnboardingSkipped` / `OnboardingCompleted`: write prefs flag → emit terminal state consumed by `BlocListener` for navigation

---

## Shared Widgets Used

| Widget | Where used |
|---|---|
| `ConicOrbPainter` | Splash — spinning gradient ring |
| `PulseRings` | Splash (3 rings) + Slide 2 (3 rings) |
| `ParticleField` | Splash background (40 particles) |
| `GradientText` | Splash "USYNC" wordmark |
| `GlowButton` | Onboarding next/finish button (circular variant) |
| `LoadingDots` | Not used here |
| `PresenceVisual` | Slide 4 — self-contained widget in onboarding/widgets/ |
| `ConnectedOrbsVisual` | Slide 1 — self-contained widget in onboarding/widgets/ |
| `EmotionWaveVisual` | Slide 2 — self-contained widget in onboarding/widgets/ |
| `DoodleVisual` | Slide 3 — CustomPainter widget in onboarding/widgets/ |
