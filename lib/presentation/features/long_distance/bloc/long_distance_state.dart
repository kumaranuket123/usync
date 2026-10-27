part of 'long_distance_bloc.dart';

/// What the Home card shows. [visible] is false unless the couple is long-distance.
final class LongDistanceState {
  const LongDistanceState({this.visible = false, this.distanceMetres, this.nextMeetOn, this.error});

  final bool      visible;
  /// Null until both partners share a location.
  final double?   distanceMetres;
  /// A date in the past counts as not set.
  final DateTime? nextMeetOn;
  final String?   error;

  /// Whole days from [today] to the next meeting (0 = today), or null when none is planned.
  int? daysUntilMeet(DateTime today) {
    final d = nextMeetOn;
    if (d == null) return null;
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    return days < 0 ? null : days;
  }
}
