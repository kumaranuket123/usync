import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usync/data/datasources/local/prefs_source.dart';
import 'package:usync/data/repositories/access_repository.dart';
import 'package:usync/domain/entities/access.dart';

import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late PrefsSource prefs;
  late AccessRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = FakeBackend();
    prefs = PrefsSource(prefs: await SharedPreferences.getInstance());
    repo = AccessRepository(client: backend.client, prefs: prefs, timeout: const Duration(seconds: 2));
  });

  tearDown(() => backend.dispose());

  const configJson = {
    'min_supported_build': 8, 'latest_build': 9, 'update_url': 'https://x.test/app.apk',
    'paywall_enabled': true, 'trial_days': 14,
  };

  group('getConfig', () {
    test('reads the server switches and saves them on the phone', () async {
      backend.respond((_) => FakeBackend.ok(configJson));

      final config = await repo.getConfig();

      expect(backend.requests.single.path, endsWith('/rpc/get_app_config'));
      expect(config.minSupportedBuild, 8);
      expect(config.paywallEnabled, isTrue);
      expect(prefs.appConfigCache, isNotNull);
    });

    test('without a connection it uses the last saved copy', () async {
      backend.respond((_) => FakeBackend.ok(configJson));
      await repo.getConfig();

      backend.respond((_) => FakeBackend.error('500', 'down', status: 500));
      final config = await repo.getConfig();

      expect(config.minSupportedBuild, 8, reason: 'the saved copy, so an old build stays blocked offline');
    });

    test('with nothing saved and no connection it never blocks anyone', () async {
      backend.respond((_) => FakeBackend.error('500', 'down', status: 500));

      final config = await repo.getConfig();

      expect(config.isUpdateRequired(1), isFalse);
      expect(config.paywallEnabled, isFalse);
    });
  });

  group('getAccess', () {
    test('asks the server about this couple', () async {
      backend.respond((_) => FakeBackend.ok({'state': 'trial', 'until': '2026-12-12T00:00:00Z', 'paywall_enabled': true}));

      final access = await repo.getAccess('c1');

      final call = backend.requests.single;
      expect(call.path, endsWith('/rpc/get_access'));
      expect(call.json, {'p_couple': 'c1'});
      expect(access.status, AccessStatus.trial);
      expect(access.paywallEnabled, isTrue);
    });

    test('if the server cannot be reached the couple keeps full access', () async {
      backend.respond((_) => FakeBackend.error('500', 'down', status: 500));

      final access = await repo.getAccess('c1');

      expect(access.status, AccessStatus.free);
      expect(access.paywallEnabled, isFalse);
    });
  });
}
