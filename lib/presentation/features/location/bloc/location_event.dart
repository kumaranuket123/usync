part of 'location_bloc.dart';

sealed class LocationEvent { const LocationEvent(); }
final class LocationScreenMounted extends LocationEvent {
  LocationScreenMounted({required this.coupleId, required this.userId, required this.partnerUserId});
  final String coupleId, userId, partnerUserId;
}
final class LocationSharingToggled    extends LocationEvent {}
final class LocateRequested          extends LocationEvent {}
final class BackgroundToggled         extends LocationEvent {}
final class BackgroundPermissionRechecked extends LocationEvent {}
final class PartnerLocationChanged    extends LocationEvent { PartnerLocationChanged(this.location); final SharedLocation? location; }
final class LocationRefreshed         extends LocationEvent {}
final class LocationSettingsRequested extends LocationEvent {}
