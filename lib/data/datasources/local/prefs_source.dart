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
