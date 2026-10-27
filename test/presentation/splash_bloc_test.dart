import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usync/data/datasources/local/prefs_source.dart';
import 'package:usync/domain/entities/access.dart';
import 'package:usync/domain/entities/app_config.dart';
import 'package:usync/domain/entities/user.dart';
import 'package:usync/domain/repositories/i_access_repository.dart';
import 'package:usync/domain/repositories/i_auth_repository.dart';
import 'package:usync/presentation/features/splash/bloc/splash_bloc.dart';

class _FakeAuth implements IAuthRepository {
  AppUser? user;
  @override
  Future<AppUser?> getCurrentUser() async => user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccess implements IAccessRepository {
  AppConfig config = const AppConfig.open();
  @override
  Future<AppConfig> getConfig() async => config;
  @override
  Future<Access> getAccess(String coupleId) async => const Access.open();
}

void main() {
  late _FakeAuth auth;
  late _FakeAccess access;
  late PrefsSource prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PrefsSource(prefs: await SharedPreferences.getInstance());
    auth = _FakeAuth();
    access = _FakeAccess();
  });

  Future<SplashDestination> run({int build = 5}) async {
    final bloc = SplashBloc(
      authRepository: auth,
      prefsSource: prefs,
      accessRepository: access,
      minDisplay: Duration.zero,
      buildNumber: () async => build,
    )..add(SplashStarted());
    addTearDown(bloc.close);
    final s = await bloc.stream.firstWhere((s) => s is SplashNavigating) as SplashNavigating;
    return s.destination;
  }

  test('a build older than the server minimum goes to the update screen', () async {
    access.config = const AppConfig(minSupportedBuild: 6);
    expect(await run(build: 5), SplashDestination.updateRequired);
  });

  test('even a signed-in user is stopped by an outdated build', () async {
    auth.user = AppUser(id: 'u', username: 'A', email: '', avatarEmoji: '🦋', createdAt: DateTime(2026), coupleId: 'c');
    access.config = const AppConfig(minSupportedBuild: 6);
    expect(await run(build: 5), SplashDestination.updateRequired);
  });

  test('an up-to-date build carries on as before', () async {
    access.config = const AppConfig(minSupportedBuild: 5);
    expect(await run(build: 5), SplashDestination.onboarding);

    auth.user = AppUser(id: 'u', username: 'A', email: '', avatarEmoji: '🦋', createdAt: DateTime(2026), coupleId: 'c');
    expect(await run(build: 5), SplashDestination.home);
  });

  test('with the default (open) config nobody is blocked', () async {
    expect(await run(build: 1), SplashDestination.onboarding);
  });
}
