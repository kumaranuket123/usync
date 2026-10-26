import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/notification_item.dart';
import '../../domain/entities/shared_location.dart';
import '../../domain/repositories/i_location_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/local/prefs_source.dart';

/// Each user's last known location is one row in `locations`, refreshed when
/// they open the app (see `LocationSyncService`). Nothing is tracked in between.
class LocationRepository implements ILocationRepository {
  LocationRepository({required this.client, required this.prefs, required this.notifications});

  final SupabaseClient          client;
  final PrefsSource             prefs;
  final INotificationRepository notifications;

  /// Looking at the map repeatedly must not buzz the partner every time.
  static const _notifyEvery = Duration(minutes: 15);

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
      return SyncResult(LocationAccess.granted, await _save(coupleId, userId, last));
    }
    return SyncResult(LocationAccess.granted, await _save(coupleId, userId, pos));
  }

  Future<SharedLocation> _save(String coupleId, String userId, Position p) async {
    // Columns not listed (allow_background) are left as they are on conflict.
    final row = await client.from('locations').upsert({
      'user_id':    userId,
      'couple_id':  coupleId,
      'latitude':   p.latitude,
      'longitude':  p.longitude,
      'accuracy':   p.accuracy,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).select().single();
    return _fromRow(row);
  }

  static SharedLocation _fromRow(Map<String, dynamic> row) => SharedLocation(
        latitude:         (row['latitude']  as num).toDouble(),
        longitude:        (row['longitude'] as num).toDouble(),
        accuracy:         (row['accuracy']  as num).toDouble(),
        timestamp:        DateTime.parse(row['updated_at'] as String),
        allowsBackground: row['allow_background'] == true,
      );

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
      .map((rows) => rows.isEmpty ? null : _fromRow(rows.first))
      .handleError((Object _) {}); // dropped Realtime connection: keep the screen alive

  @override
  Future<LocationAccess> enableBackground(String userId) async {
    var permission = await Geolocator.checkPermission();
    // Whenever-in-use is not enough: the OS only lets a closed app read the
    // location with "always".
    if (permission != LocationPermission.always) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.always) return LocationAccess.backgroundDenied;
    await client.from('locations').update({'allow_background': true}).eq('user_id', userId);
    return LocationAccess.granted;
  }

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

  @override
  Future<void> notifyPartnerViewing(String coupleId, String userId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - prefs.locationViewNotifiedAt < _notifyEvery.inMilliseconds) return;
    await prefs.setLocationViewNotifiedAt(now);
    await notifications.notifyPartner(
      coupleId:   coupleId,
      fromUserId: userId,
      type:       NotifType.location,
      body:       (name) => '$name is looking at your location 👀',
    );
  }
}
