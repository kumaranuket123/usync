import '../entities/shared_location.dart';

enum LocationAccess { granted, denied, deniedForever, serviceDisabled, backgroundDenied }

abstract interface class ILocationRepository {
  /// Whether the user opted in to refreshing their location whenever the app opens.
  bool get sharingEnabled;
  Future<void> setSharingEnabled(bool enabled);

  /// Opens the device settings page for the given [LocationAccess] problem.
  Future<void> openSettings(LocationAccess access);

  /// Reads the device position and saves it as our last known location. With
  /// [prompt] false a missing permission is reported instead of requested.
  /// Returns the saved location in [SyncResult.location] when access is granted.
  Future<SyncResult> syncOwnLocation(String coupleId, String userId, {required bool prompt});

  /// Removes our saved location so the partner can no longer see it.
  Future<void> clearOwnLocation(String userId);

  Future<SharedLocation?> getPartnerLocation(String partnerUserId);

  /// Live updates of the partner's saved location (null when they have none).
  Stream<SharedLocation?> watchPartnerLocation(String partnerUserId);

  /// Lets the partner request our location while the app is closed. Needs the
  /// "always" permission; returns [LocationAccess.backgroundDenied] without it.
  Future<LocationAccess> enableBackground(String userId);
  Future<void> disableBackground(String userId);

  /// Asks the partner's phone for a fresh fix. Only delivered if they opted in,
  /// and they always get a visible notification.
  Future<void> requestPartnerLocation(String coupleId, String userId);

  /// Pushes "your partner is looking at your location" (rate-limited).
  Future<void> notifyPartnerViewing(String coupleId, String userId);
}

class SyncResult {
  const SyncResult(this.access, [this.location]);
  final LocationAccess  access;
  final SharedLocation? location;
}
