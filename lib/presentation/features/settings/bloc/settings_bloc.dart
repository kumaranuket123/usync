import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/datasources/local/prefs_source.dart';

part 'settings_event.dart';
part 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({required this.prefsSource}) : super(const SettingsState()) {
    on<SettingsLoaded>(_onLoaded);
    on<ToggleChanged>(_onToggle);
  }

  final PrefsSource prefsSource;

  void _onLoaded(SettingsLoaded _, Emitter<SettingsState> emit) {
    emit(SettingsState(toggles: {
      'notifications': prefsSource.notificationsEnabled,
      'haptic':        prefsSource.hapticEnabled,
      'animations':    prefsSource.animationsEnabled,
    }));
  }

  Future<void> _onToggle(ToggleChanged e, Emitter<SettingsState> emit) async {
    emit(state.withToggle(e.key, e.value));
    await prefsSource.setToggle(e.key, e.value);
  }
}
