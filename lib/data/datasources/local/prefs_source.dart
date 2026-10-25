import 'package:shared_preferences/shared_preferences.dart';

class PrefsSource {
  const PrefsSource({required this.prefs});
  final SharedPreferences prefs;

  // ── Onboarding ────────────────────────────────────────────────
  bool get onboardingSeen => prefs.getBool('onboarding_seen') ?? false;
  Future<void> setOnboardingSeen() => prefs.setBool('onboarding_seen', true);

  // ── Theme ─────────────────────────────────────────────────────
  String get themeId => prefs.getString('theme_id') ?? 'midnightPurple';
  Future<void> setThemeId(String id) => prefs.setString('theme_id', id);

  // ── Settings toggles ──────────────────────────────────────────
  bool get notificationsEnabled => prefs.getBool('setting_notifications') ?? true;
  bool get hapticEnabled        => prefs.getBool('setting_haptic')        ?? true;
  bool get animationsEnabled    => prefs.getBool('setting_animations')    ?? true;

  Future<void> setToggle(String key, bool value) =>
      prefs.setBool('setting_$key', value);

  // ── Push token ────────────────────────────────────────────────
  /// The token last written to the server for [uid] and when (ms since epoch).
  ({String token, int savedAt})? fcmSaved(String uid) {
    final raw = prefs.getString('fcm_saved:$uid');
    final i   = raw?.lastIndexOf('|') ?? -1;
    if (raw == null || i < 0) return null;
    final at = int.tryParse(raw.substring(i + 1));
    return at == null ? null : (token: raw.substring(0, i), savedAt: at);
  }

  Future<void> setFcmSaved(String uid, String token) =>
      prefs.setString('fcm_saved:$uid', '$token|${DateTime.now().millisecondsSinceEpoch}');

  Future<void> clearFcmSaved(String uid) => prefs.remove('fcm_saved:$uid');

  // ── App lock ──────────────────────────────────────────────────
  bool get appLockEnabled => prefs.getBool('app_lock') ?? false;
  Future<void> setAppLockEnabled(bool value) => prefs.setBool('app_lock', value);

  // ── Location sharing ──────────────────────────────────────────
  bool get locationSharing => prefs.getBool('location_sharing') ?? false;
  Future<void> setLocationSharing(bool value) => prefs.setBool('location_sharing', value);

  /// When we last told the partner we looked at their location (ms since epoch).
  int get locationViewNotifiedAt => prefs.getInt('location_view_notified_at') ?? 0;
  Future<void> setLocationViewNotifiedAt(int ms) => prefs.setInt('location_view_notified_at', ms);

  // ── Clear (sign-out) ──────────────────────────────────────────
  Future<void> clearSession() async {
    await prefs.remove('onboarding_seen');
    // Preserve theme_id across sign-out — intentional.
  }
}
