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

  /// Off unless the user switched it on: archived memory pictures are also copied
  /// to the gallery's "Usync" album.
  bool get galleryBackupEnabled => prefs.getBool('setting_gallery_backup') ?? false;

  /// Memory ids already copied to the gallery, so none is saved twice.
  Set<String> get gallerySavedIds => (prefs.getStringList('gallery_saved_ids') ?? const []).toSet();
  Future<void> setGallerySavedIds(Set<String> ids) => prefs.setStringList('gallery_saved_ids', ids.toList());

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

  // ── Server switches ───────────────────────────────────────────
  /// The last `get_app_config` answer (JSON), used when the server cannot be reached.
  String? get appConfigCache => prefs.getString('app_config_cache');
  Future<void> setAppConfigCache(String json) => prefs.setString('app_config_cache', json);

  // ── App lock ──────────────────────────────────────────────────
  /// On unless the user (or a phone with no screen lock) switched it off.
  bool get appLockEnabled => prefs.getBool('app_lock') ?? true;
  Future<void> setAppLockEnabled(bool value) => prefs.setBool('app_lock', value);

  // ── Location sharing ──────────────────────────────────────────
  bool get locationSharing => prefs.getBool('location_sharing') ?? false;
  Future<void> setLocationSharing(bool value) => prefs.setBool('location_sharing', value);

  // ── Clear (sign-out) ──────────────────────────────────────────
  Future<void> clearSession() async {
    await prefs.remove('onboarding_seen');
    // Choices that belong to the account, not the phone: the next person to sign
    // in must start from the defaults (and must never inherit "share my
    // location" or a switched-off push setting).
    await prefs.remove('setting_notifications');
    await prefs.remove('location_sharing');
    await prefs.remove('location_view_notified_at');
    await prefs.remove('app_lock');
    await prefs.remove('setting_gallery_backup');
    await prefs.remove('gallery_saved_ids');
    // Preserve theme_id, haptics and animations across sign-out: those are about the phone.
  }
}
