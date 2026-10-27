# Feature: App lock

Optional biometric lock for the whole app: fingerprint or face, with fallback to the device PIN, pattern or password (`local_auth`). Toggle lives in [settings](settings.md).

---

## Behaviour (`AppLockService`)

- **Locked** on a cold start and whenever the app goes to the background (`paused`), if enabled and a user is signed in. Nothing to protect on the sign-in screen, so it only applies while authenticated.
- **Obscured**: while locked or when the app is hidden/inactive, the UI shows a cover instead of content, so the app-switcher preview reveals nothing. `AppLockGate` (`presentation/shared/widgets/app_lock_gate.dart`) renders the cover and the unlock prompt.
- On Android, `inactive` also fires for the notification shade, so it is not treated as hiding; instead `MainActivity` sets `FLAG_SECURE` natively to blank the recents preview while the lock is on.
- **Turning it on or off requires passing the prompt once**, so someone with an unlocked phone cannot disable it.
- If the device no longer has a screen lock or biometrics, the lock switches itself off rather than locking the user out (`_disableIfUnavailable`).
- The system prompt pauses the app; `_authenticating` prevents that from re-locking.

## State

`AppLockService extends ChangeNotifier` with `WidgetsBindingObserver`; getters `enabled`, `locked`, `obscured`. The preference is stored via `PrefsSource.appLockEnabled`. It is registered in `core/di/injection.dart` and initialised at startup.

## Edge cases

Failed prompt re-checks availability; backgrounding during authentication does not re-lock; a different signed-in account never unlocks another (the lock is inactive when signed out).
