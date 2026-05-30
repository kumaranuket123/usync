part of 'widgets_bloc.dart';
sealed class WidgetsBlocEvent { const WidgetsBlocEvent(); }
final class WidgetsLoaded extends WidgetsBlocEvent { WidgetsLoaded(this.coupleId); final String coupleId; }
