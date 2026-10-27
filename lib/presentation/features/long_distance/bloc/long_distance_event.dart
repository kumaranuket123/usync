part of 'long_distance_bloc.dart';

sealed class LongDistanceEvent { const LongDistanceEvent(); }
final class LongDistanceStarted extends LongDistanceEvent {
  LongDistanceStarted({required this.coupleId, required this.userId, required this.partnerId});
  final String coupleId, userId, partnerId;
}
final class _CoupleChanged extends LongDistanceEvent {
  _CoupleChanged(this.couple);
  final Couple couple;
}
final class _PartnerLocationChanged extends LongDistanceEvent {
  _PartnerLocationChanged(this.location);
  final SharedLocation? location;
}
/// Sets the next meeting, or clears it with a null [day].
final class NextMeetChosen extends LongDistanceEvent {
  NextMeetChosen(this.day);
  final DateTime? day;
}
