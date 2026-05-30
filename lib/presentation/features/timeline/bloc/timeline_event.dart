part of 'timeline_bloc.dart';
sealed class TimelineEvent { const TimelineEvent(); }
final class TimelineLoaded extends TimelineEvent { TimelineLoaded(this.coupleId); final String coupleId; }
