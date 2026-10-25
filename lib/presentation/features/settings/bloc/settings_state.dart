part of 'settings_bloc.dart';
class SettingsState {
  const SettingsState({this.toggles = const {}, this.silentTypes = NotifType.defaultSilent});
  final Map<String, bool> toggles;
  /// Alert groups that arrive without sound or popup.
  final Set<String> silentTypes;

  bool get notificationsEnabled => toggles['notifications'] ?? true;
  bool get hapticEnabled        => toggles['haptic']        ?? true;
  bool get animationsEnabled    => toggles['animations']    ?? true;

  SettingsState withToggle(String key, bool value) =>
      SettingsState(toggles: {...toggles, key: value}, silentTypes: silentTypes);

  SettingsState withSilentTypes(Set<String> types) =>
      SettingsState(toggles: toggles, silentTypes: types);
}
