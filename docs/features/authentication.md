# Feature: Authentication

---

## Screens

### 1. LoginScreen (`/login`)
Entry point for returning users. Minimal glass form over a dark gradient background with floating particles.

**Elements:**
- Usync gradient logo wordmark
- Heading: "Welcome back" + subtitle
- Email `GlassInput` with envelope icon
- Password `GlassInput` with lock icon, obscure toggle
- "Forgot password?" link (right-aligned)
- `GlowButton` — "Continue"
- Divider line
- "New here? Create account" link → navigates to RegisterScreen

### 2. RegisterScreen (`/register`)
New account creation. Scrollable to accommodate all fields plus the avatar grid.

**Elements:**
- `NeonBackButton` → LoginScreen
- Usync wordmark + heading "Create your space"
- Avatar emoji grid (8 options, tap-to-select with glow ring):
  `🦋 🌸 🌙 ⭐ 🔮 🌊 🌺 ✨`
- Username `GlassInput` with person icon
- Email `GlassInput` with envelope icon
- Password `GlassInput` with lock icon
- `GlowButton` — "Create Account"
- "Already paired? Sign in" link → LoginScreen

---

## User Flows

### Sign In
```
LoginScreen
  → user enters email + password
  → taps "Continue"
  → AuthBloc.SignInRequested emitted
  → AuthLoading state → button shows LoadingDots
  → success → AuthBloc checks coupleId on User entity
      → coupleId present → navigate to /home (show BottomNav)
      → coupleId absent  → navigate to /pair-invite
  → failure → AuthError state → error snackbar (e.g. "Wrong password")
```

### Sign Up
```
RegisterScreen
  → user selects avatar (default: first option)
  → fills username, email, password
  → taps "Create Account"
  → AuthBloc.SignUpRequested emitted
  → AuthLoading state
  → Firebase Auth createUser → Firestore /users/{uid} document created
  → success → navigate to /pair-invite (no coupleId yet)
  → failure → AuthError state → field-level error messages
```

### Forgot Password
```
LoginScreen → taps "Forgot password?"
  → modal bottom sheet with single email field
  → AuthBloc.PasswordResetRequested
  → Firebase Auth sendPasswordResetEmail
  → confirmation message shown in sheet
  → sheet dismisses
```

### Auth State Restoration (app launch)
```
SplashScreen
  → SplashBloc reads Firebase Auth currentUser
  → null         → navigate to /onboarding or /login
  → user exists  → fetch User from Firestore
      → coupleId present → navigate to /home
      → coupleId absent  → navigate to /pair-invite
```

### Sign Out
```
SettingsScreen → "Sign Out" tapped
  → confirmation dialog
  → AuthBloc.SignOutRequested
  → Firebase Auth signOut
  → clear Hive cache + prefs auth state
  → navigate to /login, clear all routes
```

---

## API Requirements

### Firebase Authentication
| Operation | Method |
|---|---|
| Create account | `FirebaseAuth.createUserWithEmailAndPassword` |
| Sign in | `FirebaseAuth.signInWithEmailAndPassword` |
| Sign out | `FirebaseAuth.signOut` |
| Password reset | `FirebaseAuth.sendPasswordResetEmail` |
| Auth state stream | `FirebaseAuth.authStateChanges()` |
| Current user | `FirebaseAuth.currentUser` |

### Firestore — `/users/{uid}`
| Operation | Method |
|---|---|
| Create user doc | `set({username, email, avatarEmoji, createdAt, coupleId: null})` |
| Read user doc | `get()` |
| Update coupleId | `update({coupleId: ...})` (done by PairingRepository) |

---

## Data Models

### `User` (domain entity)
```
id:           String          // Firebase Auth UID
username:     String
email:        String
avatarEmoji:  String          // single emoji character
coupleId:     String?         // null until paired
createdAt:    DateTime
```

### `UserModel` (data layer — Firestore serialisation)
Extends `User`. Implements `fromJson` / `toJson`.

```json
{
  "id":          "uid_abc123",
  "username":    "Anuket",
  "email":       "anuket@email.com",
  "avatarEmoji": "🦋",
  "coupleId":    null,
  "createdAt":   "2026-01-12T10:00:00Z"
}
```

### `AuthCredentials` (local — not persisted)
```
email:    String
password: String
```

---

## BLoC: `AuthBloc`

**Provided at:** root `MultiBlocProvider` (app-wide).

### Events
```
SignInRequested   { email: String, password: String }
SignUpRequested   { email: String, password: String, username: String, avatarEmoji: String }
SignOutRequested
PasswordResetRequested { email: String }
AuthStateChecked  // fired by SplashBloc on app start
```

### States
```
AuthInitial
AuthLoading
Authenticated         { user: User }
Unauthenticated
AuthError             { message: String }
PasswordResetSent     { email: String }
```

### Handler logic
- `SignInRequested` → `IAuthRepository.signIn` → emits `Authenticated` or `AuthError`
- `SignUpRequested` → `IAuthRepository.signUp` → creates Firestore doc → emits `Authenticated`
- `SignOutRequested` → `IAuthRepository.signOut` → clears local cache → emits `Unauthenticated`
- `AuthStateChecked` → reads `IAuthRepository.watchAuthState()` first event → routes accordingly

---

## Shared Widgets Used

| Widget | Usage |
|---|---|
| `GlassCard` | Not used directly; inputs and layout are flat on the gradient bg |
| `GlassInput` | Email, password, username fields |
| `GlowButton` | "Continue", "Create Account" CTAs |
| `OutlineButton` | Secondary actions (not present on auth screens directly) |
| `GradientText` | "USYNC" wordmark |
| `NeonBackButton` | RegisterScreen back arrow |
| `LoadingDots` | Replaces button label during `AuthLoading` |
| `ParticleField` | Background on LoginScreen (20 particles, low opacity) |
