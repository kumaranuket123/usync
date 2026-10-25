part of 'timeline_bloc.dart';
sealed class TimelineEvent { const TimelineEvent(); }
final class TimelineLoaded extends TimelineEvent { TimelineLoaded(this.coupleId); final String coupleId; }
final class DateAdded extends TimelineEvent {
  DateAdded({required this.title, required this.date, this.note, required this.emoji, required this.repeatsYearly});
  final String   title;
  /// Calendar day only; the time of day is ignored.
  final DateTime date;
  final String?  note;
  final String   emoji;
  final bool     repeatsYearly;
}
final class DateDeleted extends TimelineEvent { DateDeleted(this.id); final String id; }
