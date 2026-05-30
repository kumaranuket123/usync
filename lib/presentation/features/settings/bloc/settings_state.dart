part of 'settings_bloc.dart';
class SettingsState {
  const SettingsState({this.toggles = const {}});
  final Map<String, bool> toggles;

  bool get notificationsEnabled => toggles['notifications'] ?? true;
  bool get hapticEnabled        => toggles['haptic']        ?? true;
  bool get animationsEnabled    => toggles['animations']    ?? true;

  SettingsState withToggle(String key, bool value) =>
      SettingsState(toggles: {...toggles, key: value});
}
