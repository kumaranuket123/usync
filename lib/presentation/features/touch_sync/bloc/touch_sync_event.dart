part of 'touch_sync_bloc.dart';
sealed class TouchSyncEvent { const TouchSyncEvent(); }
final class TouchScreenMounted   extends TouchSyncEvent { TouchScreenMounted({required this.coupleId, required this.userId, required this.partnerUserId}); final String coupleId, userId, partnerUserId; }
final class TouchPressed         extends TouchSyncEvent {}
final class TouchReleased        extends TouchSyncEvent {}
final class RemoteTouchReceived  extends TouchSyncEvent { RemoteTouchReceived(this.isActive); final bool isActive; }
final class ConnectionLost       extends TouchSyncEvent {}
