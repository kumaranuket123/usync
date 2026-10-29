import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/local/flutter_secure_key_store.dart';
import '../../data/datasources/local/prefs_source.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../../domain/repositories/i_location_repository.dart';
import '../constants/supabase_config.dart';
import '../crypto/content_cipher.dart';
import '../crypto/key_service.dart';

/// Refreshes the user's saved location each time the app opens or returns to
/// the foreground, if they turned sharing on. Never prompts for permission.
class LocationSyncService with WidgetsBindingObserver {
  LocationSyncService._();

  /// Opening the app twice in quick succession should not re-read the GPS.
  static const _minGap = Duration(minutes: 2);
  DateTime? _lastSync;

  static void init() {
    final service = LocationSyncService._();
    WidgetsBinding.instance.addObserver(service);
    service.sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sync();
  }

  Future<void> sync() async {
    final locations = GetIt.I<ILocationRepository>();
    if (!locations.sharingEnabled) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final last = _lastSync;
    if (last != null && DateTime.now().difference(last) < _minGap) return;
    _lastSync = DateTime.now();

    try {
      final user = await GetIt.I<IAuthRepository>().getCurrentUser();
      final coupleId = user?.coupleId;
      if (coupleId == null) return;
      await locations.syncOwnLocation(coupleId, uid, prompt: false);
    } catch (_) {
      // Best effort: a failed refresh just leaves the previous location in place.
    }
  }

  /// Answers a partner's "locate" request. Runs in the push background isolate,
  /// where GetIt is not set up, so it builds what it needs directly. Does
  /// nothing unless the user opted in to background location.
  static Future<void> answerLocateRequest() async {
    try {
      try {
        Supabase.instance.client;
      } catch (_) {
        await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey);
      }
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;

      final own = await client.from('locations').select('allow_background').eq('user_id', uid).maybeSingle();
      if (own?['allow_background'] != true) return;

      final profile = await client.from('profiles').select('couple_id').eq('id', uid).maybeSingle();
      final coupleId = profile?['couple_id'] as String?;
      if (coupleId == null) return;

      final prefs = PrefsSource(prefs: await SharedPreferences.getInstance());
      // In this background task there is no service registry: read the keys straight from secure storage.
      final cipher = ContentCipher(
        keysFor: (userId) => KeyService(store: const FlutterSecureKeyStore(), namespace: userId),
        currentUserId: () => client.auth.currentUser?.id,
      );
      await LocationRepository(
        client:        client,
        prefs:         prefs,
        notifications: NotificationRepository(client: client, cipher: cipher),
        cipher:        cipher,
      ).syncOwnLocation(coupleId, uid, prompt: false);
    } catch (_) {
      // Best effort: the requester simply keeps seeing the older location.
    }
  }
}
