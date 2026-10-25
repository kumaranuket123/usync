import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/datasources/local/prefs_source.dart';
import '../../../../domain/entities/notification_item.dart';
import '../../../../domain/repositories/i_notification_repository.dart';

part 'settings_event.dart';
part 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({required this.prefsSource, required this.notifications}) : super(const SettingsState()) {
    on<SettingsLoaded>(_onLoaded);
    on<AlertTypesRequested>(_onAlertTypesRequested);
    on<ToggleChanged>(_onToggle);
    on<AlertSilenceChanged>(_onAlertSilence);
  }

  final PrefsSource             prefsSource;
  final INotificationRepository notifications;

  Future<void> _onLoaded(SettingsLoaded _, Emitter<SettingsState> emit) async {
    emit(SettingsState(toggles: {
      'notifications': prefsSource.notificationsEnabled,
      'haptic':        prefsSource.hapticEnabled,
      'animations':    prefsSource.animationsEnabled,
    }));
  }

  /// Stored on the server (the sender's push is built there), so it is read
  /// when the Settings screen is first opened rather than at every app start.
  Future<void> _onAlertTypesRequested(AlertTypesRequested _, Emitter<SettingsState> emit) async {
    if (state.silentTypesLoaded) return;
    try {
      emit(state.withSilentTypes(await notifications.getSilentTypes()));
    } catch (_) {
      // Offline or signed out: keep the defaults; the next visit tries again.
    }
  }

  Future<void> _onToggle(ToggleChanged e, Emitter<SettingsState> emit) async {
    emit(state.withToggle(e.key, e.value));
    await prefsSource.setToggle(e.key, e.value);
  }

  Future<void> _onAlertSilence(AlertSilenceChanged e, Emitter<SettingsState> emit) async {
    final before = state.silentTypes;
    final after  = e.silent ? {...before, e.group} : ({...before}..remove(e.group));
    emit(state.withSilentTypes(after));
    try {
      await notifications.setSilentTypes(after);
    } catch (_) {
      emit(state.withSilentTypes(before)); // not saved: show the real setting
    }
  }
}
