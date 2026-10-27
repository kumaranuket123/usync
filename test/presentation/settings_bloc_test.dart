import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usync/data/datasources/local/prefs_source.dart';
import 'package:usync/domain/entities/notification_item.dart';
import 'package:usync/domain/repositories/i_notification_repository.dart';
import 'package:usync/presentation/features/settings/bloc/settings_bloc.dart';

class _FakeNotifications implements INotificationRepository {
  Set<String> silent = {'location'};
  bool getFails = false;
  bool setFails = false;
  int gets = 0;
  final saved = <Set<String>>[];

  @override
  Future<Set<String>> getSilentTypes() async {
    gets++;
    if (getFails) throw Exception('offline');
    return silent;
  }

  @override
  Future<void> setSilentTypes(Set<String> types) async {
    if (setFails) throw Exception('offline');
    saved.add(types);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late PrefsSource prefs;
  late _FakeNotifications notifications;
  late SettingsBloc bloc;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> build([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    prefs = PrefsSource(prefs: await SharedPreferences.getInstance());
    notifications = _FakeNotifications();
    bloc = SettingsBloc(prefsSource: prefs, notifications: notifications);
  }

  tearDown(() => bloc.close());

  test('loading applies the defaults', () async {
    await build();
    bloc.add(const SettingsLoaded());
    await settle();
    expect(bloc.state.notificationsEnabled, isTrue);
    expect(bloc.state.hapticEnabled, isTrue);
    expect(bloc.state.animationsEnabled, isTrue);
    expect(bloc.state.galleryBackupEnabled, isFalse);
  });

  test('loading reads saved values', () async {
    await build({'setting_haptic': false, 'setting_gallery_backup': true});
    bloc.add(const SettingsLoaded());
    await settle();
    expect(bloc.state.hapticEnabled, isFalse);
    expect(bloc.state.galleryBackupEnabled, isTrue);
  });

  test('a toggle updates the state and is persisted', () async {
    await build();
    bloc.add(const SettingsLoaded());
    bloc.add(const ToggleChanged(key: 'animations', value: false));
    await settle();
    expect(bloc.state.animationsEnabled, isFalse);
    expect(prefs.animationsEnabled, isFalse);
  });

  test('alert types are fetched once and kept', () async {
    await build();
    notifications.silent = {'touch', 'location'};
    bloc.add(const AlertTypesRequested());
    await settle();
    bloc.add(const AlertTypesRequested());
    await settle();
    expect(bloc.state.silentTypes, {'touch', 'location'});
    expect(bloc.state.silentTypesLoaded, isTrue);
    expect(notifications.gets, 1);
  });

  test('offline alert-type fetch keeps the defaults and tries again next time', () async {
    await build();
    notifications.getFails = true;
    bloc.add(const AlertTypesRequested());
    await settle();
    expect(bloc.state.silentTypes, NotifType.defaultSilent);
    expect(bloc.state.silentTypesLoaded, isFalse);

    notifications.getFails = false;
    bloc.add(const AlertTypesRequested());
    await settle();
    expect(bloc.state.silentTypesLoaded, isTrue);
  });

  test('silencing an alert group saves it to the server', () async {
    await build();
    bloc.add(const AlertSilenceChanged(group: 'touch', silent: true));
    await settle();
    expect(bloc.state.silentTypes, {'location', 'touch'});
    expect(notifications.saved.single, {'location', 'touch'});
  });

  test('un-silencing removes the group', () async {
    await build();
    bloc.add(const AlertSilenceChanged(group: 'location', silent: false));
    await settle();
    expect(bloc.state.silentTypes, isEmpty);
  });

  test('a failed save restores the previous alert setting', () async {
    await build();
    notifications.setFails = true;
    bloc.add(const AlertSilenceChanged(group: 'touch', silent: true));
    await settle();
    expect(bloc.state.silentTypes, NotifType.defaultSilent);
  });
}
