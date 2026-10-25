import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

import '../../data/datasources/local/prefs_source.dart';

/// Optional lock for the whole app: fingerprint / face, falling back to the
/// device PIN, pattern or password. The app is locked on a cold start and every
/// time it goes to the background, and its contents are hidden from the
/// app-switcher preview while the lock is on.
class AppLockService extends ChangeNotifier with WidgetsBindingObserver {
  AppLockService({required this.prefs});
  final PrefsSource prefs;

  final _auth = LocalAuthentication();

  bool _locked     = false;
  bool _obscured   = false;
  /// The system prompt briefly pauses the app; that must not re-lock it.
  bool _authenticating = false;

  bool get enabled  => prefs.appLockEnabled;
  bool get locked   => _locked;
  /// Show the cover (lock screen or blank) instead of the app contents.
  bool get obscured => enabled && (_locked || _obscured);

  void init() {
    WidgetsBinding.instance.addObserver(this);
    if (enabled) {
      _locked = true;
      _disableIfUnavailable();
    }
  }

  /// The lock needs a fingerprint, face or screen lock on the phone. If the
  /// user later removes it there is nothing to unlock with, so the lock is
  /// switched off instead of leaving them out of their own app.
  Future<void> _disableIfUnavailable() async {
    if (await isAvailable) return;
    await prefs.setAppLockEnabled(false);
    _locked   = false;
    _obscured = false;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!enabled || _authenticating) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _obscured = false;
      case AppLifecycleState.paused:
        _locked = true;
        _obscured = true;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _obscured = true;
      case AppLifecycleState.detached:
        break;
    }
    notifyListeners();
  }

  Future<bool> get isAvailable async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _prompt(String reason) async {
    _authenticating = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // Not biometric-only: someone whose fingerprint fails can still use the PIN.
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    } finally {
      _authenticating = false;
    }
  }

  /// Prompts to unlock. Returns whether the app is now unlocked.
  Future<bool> unlock() async {
    if (!_locked) return true;
    if (!await _prompt('Unlock Usync')) {
      // A failed prompt may mean the phone no longer has anything to unlock with.
      await _disableIfUnavailable();
      return !_locked;
    }
    _locked = false;
    _obscured = false;
    notifyListeners();
    return true;
  }

  /// Turning the lock on or off requires passing the prompt once, so nobody
  /// can switch it off from an unlocked phone they just picked up. Returns
  /// false when it could not be changed.
  Future<bool> setEnabled(bool value) async {
    if (value == enabled) return true;
    if (value && !await isAvailable) return false;
    if (!await _prompt(value ? 'Turn on app lock' : 'Turn off app lock')) return false;
    await prefs.setAppLockEnabled(value);
    _locked = false;
    _obscured = false;
    notifyListeners();
    return true;
  }
}
