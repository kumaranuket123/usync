part of 'widgets_bloc.dart';

sealed class WidgetsBlocState {}

final class WidgetsLoading extends WidgetsBlocState {}

final class WidgetsReady extends WidgetsBlocState {
  WidgetsReady({required this.couple, this.partnerMood});
  final Couple couple;
  final Mood? partnerMood;
}
