part of 'settings_bloc.dart';
sealed class SettingsEvent { const SettingsEvent(); }
final class SettingsLoaded extends SettingsEvent { const SettingsLoaded() : super(); }
final class ToggleChanged extends SettingsEvent {
  const ToggleChanged({required this.key, required this.value}) : super();
  final String key;
  final bool value;
}
