part of 'settings_bloc.dart';
sealed class SettingsEvent { const SettingsEvent(); }
final class SettingsLoaded extends SettingsEvent { const SettingsLoaded() : super(); }
/// The Settings screen was opened: load the alert sound choices from the server
/// (once; they are kept after that).
final class AlertTypesRequested extends SettingsEvent { const AlertTypesRequested() : super(); }
final class ToggleChanged extends SettingsEvent {
  const ToggleChanged({required this.key, required this.value}) : super();
  final String key;
  final bool value;
}
/// Sets one alert group (see NotifType.soundGroup) to silent or to make a sound.
final class AlertSilenceChanged extends SettingsEvent {
  const AlertSilenceChanged({required this.group, required this.silent}) : super();
  final String group;
  final bool silent;
}
