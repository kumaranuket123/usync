import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/data/datasources/local/prefs_source.dart';
import 'package:usync/data/repositories/location_repository.dart';
import 'package:usync/domain/repositories/i_location_repository.dart';

import '../support/test_cipher.dart';
import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late RecordingNotifications notifications;
  late SharedPreferences prefs;
  late ContentCipher cipher;
  late LocationRepository repo;

  LocationRepository build(ContentCipher c) => LocationRepository(
        client: backend.client,
        prefs: PrefsSource(prefs: prefs),
        notifications: notifications,
        cipher: c,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    backend = FakeBackend();
    notifications = RecordingNotifications();
    cipher = await readyCipher();
    repo = build(cipher);
  });

  tearDown(() => backend.dispose());

  group('saving', () {
    test('the position goes up only as ciphertext, and clears any older readable position', () async {
      // The upsert asks for the saved row back: echo what was sent.
      backend.respond((r) => FakeBackend.ok({...(r.json as Map<String, dynamic>), 'allow_background': true}));

      final saved = await repo.save('c1', 'u1', latitude: 12.971598, longitude: 77.594566, accuracy: 7.5);

      final row = backend.requests.single.json as Map<String, dynamic>;
      expect(row['enc'], startsWith('u1:'));
      expect(row['latitude'], isNull);
      expect(row['longitude'], isNull);
      expect(row['accuracy'], isNull);
      expect(row.containsKey('allow_background'), isFalse, reason: 'left as it is on conflict');
      for (final secret in ['12.97', '77.59', '7.5']) {
        expect(bodyText(row), isNot(contains(secret)));
      }

      final opened = await cipher.openJson(row['enc'] as String, coupleId: 'c1', table: 'locations', rowId: 'u1');
      expect(opened['lat'], 12.971598);
      expect(opened['lon'], 77.594566);

      expect(saved.latitude, 12.971598);
      expect(saved.longitude, 77.594566);
      expect(saved.accuracy, 7.5);
      expect(saved.allowsBackground, isTrue);
    });

    test('without the couple key nothing is saved', () async {
      repo = build(notReadyCipher());
      backend.respond((_) => FakeBackend.ok({}));

      await expectLater(repo.save('c1', 'u1', latitude: 1, longitude: 2, accuracy: 3), throwsA(isA<EncryptionNotReady>()));

      expect(backend.requests, isEmpty);
    });

    test('syncing without the couple key says the connection is not secured, before reading the GPS', () async {
      repo = build(notReadyCipher());

      final result = await repo.syncOwnLocation('c1', 'u1', prompt: false);

      expect(result.access, LocationAccess.notSecured);
      expect(result.location, isNull);
      expect(backend.requests, isEmpty);
    });
  });

  group('reading the partner', () {
    Future<Map<String, dynamic>> sealed(String userId, {ContentCipher? by, String at = '2026-03-01T10:00:00.000Z', String coupleId = 'c1'}) async => {
          'user_id': userId,
          'couple_id': coupleId,
          'latitude': null,
          'longitude': null,
          'accuracy': null,
          'allow_background': true,
          'updated_at': '2026-03-05T10:00:00Z',
          'enc': await (by ?? cipher).sealJson({'lat': 48.8584, 'lon': 2.2945, 'acc': 12.0, 'at': at}, coupleId: coupleId, table: 'locations', rowId: userId),
        };

    test('a sealed location is opened, with the time of the fix from inside it', () async {
      final row = await sealed('u2');
      backend.respond((_) => FakeBackend.ok(row));

      final l = (await repo.getPartnerLocation('u2'))!;

      expect(l.latitude, 48.8584);
      expect(l.longitude, 2.2945);
      expect(l.accuracy, 12.0);
      expect(l.timestamp, DateTime.utc(2026, 3, 1, 10));
      expect(l.timestamp, isNot(DateTime.utc(2026, 3, 5, 10)), reason: 'a column the server can change is not trusted for the time');
      expect(l.allowsBackground, isTrue);
    });

    test('an older readable location is still shown', () async {
      backend.respond((_) => FakeBackend.ok({
            'user_id': 'u2', 'couple_id': 'c1', 'latitude': 1.5, 'longitude': 2.5, 'accuracy': 3.0,
            'allow_background': false, 'updated_at': '2026-03-05T10:00:00Z', 'enc': null,
          }));

      final l = (await repo.getPartnerLocation('u2'))!;

      expect(l.latitude, 1.5);
      expect(l.timestamp, DateTime.utc(2026, 3, 5, 10));
    });

    test('no row means no location', () async {
      backend.respond((_) => FakeBackend.ok(null, status: 200));
      expect(await repo.getPartnerLocation('u2'), isNull);
    });

    test('a location this phone cannot read shows as none instead of failing', () async {
      final foreign = await sealed('u2', by: await readyCipher());
      backend.respond((_) => FakeBackend.ok(foreign));
      expect(await repo.getPartnerLocation('u2'), isNull);

      final row = await sealed('u2');
      backend.respond((_) => FakeBackend.ok(row));
      expect(await build(notReadyCipher()).getPartnerLocation('u2'), isNull);
    });

    test('a location copied onto another person or couple does not open', () async {
      final row = await sealed('u2');
      backend.respond((_) => FakeBackend.ok({...row, 'user_id': 'u3'}));
      expect(await repo.getPartnerLocation('u3'), isNull);

      final other = await readyCipher(coupleIds: const ['c1', 'c2']);
      backend.respond((_) => FakeBackend.ok({...row, 'couple_id': 'c2'}));
      expect(await build(other).getPartnerLocation('u2'), isNull);
    });
  });
}
