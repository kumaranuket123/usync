part of 'timeline_bloc.dart';
sealed class TimelineState {}
final class TimelineLoading extends TimelineState {}
final class TimelineReady   extends TimelineState {
  TimelineReady({required this.milestones, required this.daysTogether});
  final List<Milestone> milestones;
  final int             daysTogether;
}
final class TimelineEmpty   extends TimelineState { TimelineEmpty(this.daysTogether); final int daysTogether; }
final class TimelineError   extends TimelineState { TimelineError(this.message); final String message; }
