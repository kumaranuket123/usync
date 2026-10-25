part of 'timeline_bloc.dart';
sealed class TimelineState {}
final class TimelineLoading extends TimelineState {}
final class TimelineReady   extends TimelineState {
  TimelineReady({required this.milestones, required this.daysTogether, this.notice});
  final List<Milestone> milestones;
  final int             daysTogether;
  /// One-off message for the screen to show (e.g. a save that failed).
  final String?         notice;
}
final class TimelineEmpty   extends TimelineState { TimelineEmpty(this.daysTogether); final int daysTogether; }
final class TimelineError   extends TimelineState { TimelineError(this.message); final String message; }
