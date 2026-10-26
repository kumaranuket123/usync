part of 'location_bloc.dart';

sealed class LocationState {}
final class LocationConnecting extends LocationState {}
final class LocationReady extends LocationState {
  LocationReady({
    this.isSharing = false,
    this.isBusy    = false,
    this.isLocating = false,
    this.own,
    this.partner,
    this.access = LocationAccess.granted,
  });
  final bool            isSharing;
  /// A sync or refresh is in flight.
  final bool            isBusy;
  /// A "locate now" request is out and we are waiting for the partner's phone.
  final bool            isLocating;
  final SharedLocation? own;
  final SharedLocation? partner;
  /// Anything other than `granted` means we could not read the device location.
  final LocationAccess  access;

  LocationReady copyWith({
    bool? isSharing,
    bool? isBusy,
    bool? isLocating,
    SharedLocation? Function()? own,
    SharedLocation? Function()? partner,
    LocationAccess? access,
  }) =>
      LocationReady(
        isSharing: isSharing ?? this.isSharing,
        isBusy:    isBusy    ?? this.isBusy,
        isLocating: isLocating ?? this.isLocating,
        own:       own     != null ? own()     : this.own,
        partner:   partner != null ? partner() : this.partner,
        access:    access  ?? this.access,
      );
}
