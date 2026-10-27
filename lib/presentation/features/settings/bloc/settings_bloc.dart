import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

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
      'gallery_backup': prefsSource.galleryBackupEnabled,
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
    if (e.key == 'notifications') await _applyPushSwitch(e.value, emit);
  }

  /// The switch must actually start or stop pushes on this device: off removes its
  /// token (so the server has nowhere to send), on registers it again.
  Future<void> _applyPushSwitch(bool on, Emitter<SettingsState> emit) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      // Affects this device only; the alert-sound choices live on the profile and stay.
      await notifications.toggleFcm(enabled: on, uid: uid);
    } catch (_) {
      // Could not reach the server: show (and keep) what is really in effect.
      emit(state.withToggle('notifications', !on));
      await prefsSource.setToggle('notifications', !on);
    }
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
