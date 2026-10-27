part of 'settings_bloc.dart';
class SettingsState {
  const SettingsState({
    this.toggles = const {},
    this.silentTypes = NotifType.defaultSilent,
    this.silentTypesLoaded = false,
  });
  final Map<String, bool> toggles;
  /// Alert groups that arrive without sound or popup.
  final Set<String> silentTypes;
  /// The choices have been read from the server (they are fetched on first use).
  final bool silentTypesLoaded;

  bool get notificationsEnabled => toggles['notifications'] ?? true;
  bool get hapticEnabled        => toggles['haptic']        ?? true;
  bool get animationsEnabled    => toggles['animations']    ?? true;
  bool get galleryBackupEnabled => toggles['gallery_backup'] ?? false;

  SettingsState withToggle(String key, bool value) =>
      SettingsState(toggles: {...toggles, key: value}, silentTypes: silentTypes, silentTypesLoaded: silentTypesLoaded);

  SettingsState withSilentTypes(Set<String> types) =>
      SettingsState(toggles: toggles, silentTypes: types, silentTypesLoaded: true);
}
