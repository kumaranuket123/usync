part of 'touch_sync_bloc.dart';
sealed class TouchSyncState {}
final class TouchSyncConnecting extends TouchSyncState {}
final class TouchSyncReady extends TouchSyncState {
  TouchSyncReady({this.isOwnerTouching = false, this.isPartnerTouching = false, this.isConnected = true});
  final bool isOwnerTouching, isPartnerTouching, isConnected;
  TouchSyncReady copyWith({bool? isOwnerTouching, bool? isPartnerTouching, bool? isConnected}) =>
      TouchSyncReady(
        isOwnerTouching:   isOwnerTouching   ?? this.isOwnerTouching,
        isPartnerTouching: isPartnerTouching ?? this.isPartnerTouching,
        isConnected:       isConnected       ?? this.isConnected,
      );
}
