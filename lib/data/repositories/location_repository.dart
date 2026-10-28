import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/content_cipher.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/entities/shared_location.dart';
import '../../domain/repositories/i_location_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/local/prefs_source.dart';

/// Each user's last known location is one row in `locations`, refreshed when
/// they open the app (see `LocationSyncService`). Nothing is tracked in between.
class LocationRepository implements ILocationRepository {
  LocationRepository({required this.client, required this.prefs, required this.notifications, required this.cipher});

  final SupabaseClient          client;
  final PrefsSource             prefs;
  final INotificationRepository notifications;
  final ContentCipher           cipher;

  @override
  bool get sharingEnabled => prefs.locationSharing;

  @override
  Future<void> setSharingEnabled(bool enabled) => prefs.setLocationSharing(enabled);

  Future<LocationAccess> _access({required bool prompt}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceDisabled;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && prompt) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.denied        => LocationAccess.denied,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _                                => LocationAccess.granted,
    };
  }

  @override
  Future<void> openSettings(LocationAccess access) => access == LocationAccess.serviceDisabled
      ? Geolocator.openLocationSettings()
      : Geolocator.openAppSettings();

  @override
  Future<SyncResult> syncOwnLocation(String coupleId, String userId, {required bool prompt}) async {
    // A location is always sealed: without the couple key there is nothing to read the GPS for.
    if (!await cipher.isReady(coupleId)) return const SyncResult(LocationAccess.notSecured);
    final access = await _access(prompt: prompt);
    if (access != LocationAccess.granted) return SyncResult(access);

    final Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy:  LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      // No fix in time: fall back to whatever the OS last knew, if anything.
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) return const SyncResult(LocationAccess.granted);
      return SyncResult(LocationAccess.granted, await save(coupleId, userId, latitude: last.latitude, longitude: last.longitude, accuracy: last.accuracy));
    }
    return SyncResult(LocationAccess.granted, await save(coupleId, userId, latitude: pos.latitude, longitude: pos.longitude, accuracy: pos.accuracy));
  }

  /// Seals the fix and saves it as the person's one location row. The readable columns are set to null, so
  /// an older readable location is cleared too. Throws [EncryptionNotReady] without the couple key.
  @visibleForTesting
  Future<SharedLocation> save(String coupleId, String userId, {required double latitude, required double longitude, required double accuracy}) async {
    final now = DateTime.now().toUtc();
    final sealed = await cipher.sealJson(
      {'lat': latitude, 'lon': longitude, 'acc': accuracy, 'at': now.toIso8601String()},
      coupleId: coupleId, table: 'locations', rowId: userId,
    );
    // Columns not listed (allow_background) are left as they are on conflict.
    final row = await client.from('locations').upsert({
      'user_id':    userId,
      'couple_id':  coupleId,
      'latitude':   null,
      'longitude':  null,
      'accuracy':   null,
      'enc':        sealed,
      'updated_at': now.toIso8601String(),
    }).select().single();
    return (await _fromRow(row))!;
  }

  /// A location from its row: a sealed one is opened (and the time of the fix comes from inside it, so an
  /// old value replayed by the server shows its true age), an older readable one is used as it is. Null
  /// when this phone cannot read it (no key yet, or it was changed).
  Future<SharedLocation?> _fromRow(Map<String, dynamic> row) async {
    try {
      final sealed = row['enc'] as String?;
      if (ContentCipher.isEncrypted(sealed)) {
        final c = await cipher.openJson(sealed!, coupleId: row['couple_id'] as String, table: 'locations', rowId: row['user_id'] as String);
        return SharedLocation(
          latitude:         (c['lat'] as num).toDouble(),
          longitude:        (c['lon'] as num).toDouble(),
          accuracy:         (c['acc'] as num).toDouble(),
          timestamp:        DateTime.parse(c['at'] as String),
          allowsBackground: row['allow_background'] == true,
        );
      }
      return SharedLocation(
        latitude:         (row['latitude']  as num).toDouble(),
        longitude:        (row['longitude'] as num).toDouble(),
        accuracy:         (row['accuracy']  as num).toDouble(),
        timestamp:        DateTime.parse(row['updated_at'] as String),
        allowsBackground: row['allow_background'] == true,
      );
    } catch (e) {
      debugPrint('Could not read a location: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Future<void> clearOwnLocation(String userId) =>
      client.from('locations').delete().eq('user_id', userId);

  @override
  Future<SharedLocation?> getPartnerLocation(String partnerUserId) async {
    final row = await client.from('locations').select().eq('user_id', partnerUserId).maybeSingle();
    return row == null ? null : _fromRow(row);
  }

  @override
  Stream<SharedLocation?> watchPartnerLocation(String partnerUserId) => client
      .from('locations')
      .stream(primaryKey: ['user_id'])
      .eq('user_id', partnerUserId)
      .asyncMap((rows) async => rows.isEmpty ? null : await _fromRow(rows.first))
      .handleError((Object _) {}); // dropped Realtime connection: keep the screen alive

  @override
  Future<LocationAccess> enableBackground(String userId) async {
    var permission = await Geolocator.checkPermission();
    // Whenever-in-use is not enough: the OS only lets a closed app read the
    // location with "always".
    if (permission != LocationPermission.always) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.always) {
      // Android 11+ never shows a dialog for "all the time": the user has to pick it on
      // the app's permission page. Send them there; the screen re-checks on return.
      await Geolocator.openAppSettings();
      return LocationAccess.backgroundDenied;
    }
    await client.from('locations').update({'allow_background': true}).eq('user_id', userId);
    return LocationAccess.granted;
  }

  @override
  Future<bool> hasAlwaysPermission() async =>
      await Geolocator.checkPermission() == LocationPermission.always;

  @override
  Future<void> disableBackground(String userId) =>
      client.from('locations').update({'allow_background': false}).eq('user_id', userId);

  @override
  Future<void> requestPartnerLocation(String coupleId, String userId) =>
      notifications.notifyPartner(
        coupleId:   coupleId,
        fromUserId: userId,
        type:       NotifType.locate,
        body:       (name) => '$name checked your location 📍',
      );
}
