import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/core/crypto/crypto_service.dart';
import 'package:usync/data/models/mood_model.dart';
import 'package:usync/data/repositories/mood_repository.dart';
import 'package:usync/domain/entities/mood.dart';
import 'package:usync/domain/entities/notification_item.dart';

import '../support/test_cipher.dart';
import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late LocalStorage local;
  late RecordingNotifications notifications;
  late MoodRepository repo;
  late ContentCipher cipher;

  setUp(() async {
    backend = FakeBackend();
    local = LocalStorage();
    await local.setUp();
    notifications = RecordingNotifications();
    cipher = await readyCipher();
    repo = MoodRepository(
      client: backend.client,
      notifications: notifications,
      outbox: local.outbox,
      sessionCache: local.sessionCache,
      cipher: cipher,
    );
  });

  tearDown(() async {
    await local.tearDown();
    await backend.dispose();
  });

  group('sendMood', () {
    test('sends the mood only as ciphertext, with a client-chosen id, and notifies the partner', () async {
      backend.respond((_) => FakeBackend.ok([]));

      final reachedServer = await repo.sendMood('c1', 'u1', MoodType.missingYou);

      expect(reachedServer, isTrue);
      final insert = backend.requests.single;
      expect(insert.method, 'POST');
      expect(insert.path, endsWith('/moods'));
      final row = insert.json as Map;
      expect(row['id'], isNotEmpty);
      expect(row['couple_id'], 'c1');
      expect(row['user_id'], 'u1');
      expect(row['type'], 'custom', reason: 'only a placeholder: the real mood is inside `enc`');
      expect(row['enc'], startsWith('u1:'));
      expect(row.containsKey('custom_label'), isFalse);
      expect(bodyText(insert.json), isNot(contains('missingYou')), reason: 'the mood must not be readable in the request');
      expect(bodyText(insert.json), isNot(contains('Missing')));

      // What the partner's phone (same couple key) reads back.
      final opened = await cipher.openJson(row['enc'] as String, coupleId: 'c1', table: 'moods', rowId: row['id'] as String);
      expect(opened['type'], 'missingYou');

      final note = notifications.sent.single;
      expect(note.type, NotifType.moodChange);
      expect(note.fromUserId, 'u1');
      expect(note.body, 'Alex shared a mood 💭', reason: 'the push says only a fixed sentence');
      expect(note.body, isNot(contains('Missing')));
      expect(note.detail, 'Alex is feeling Missing You 💖', reason: 'the specific mood goes only into the encrypted detail');
    });

    test('a ciphertext made for one row does not open as another row', () async {
      backend.respond((_) => FakeBackend.ok([]));
      await repo.sendMood('c1', 'u1', MoodType.happy);
      final row = backend.requests.single.json as Map;
      await expectLater(
        cipher.openJson(row['enc'] as String, coupleId: 'c1', table: 'moods', rowId: 'some-other-mood'),
        throwsA(isA<CryptoException>()),
      );
    });

    test('without the couple key nothing is sent or queued, and the caller is told', () async {
      repo = MoodRepository(
        client: backend.client,
        notifications: notifications,
        outbox: local.outbox,
        sessionCache: local.sessionCache,
        cipher: notReadyCipher(),
      );
      backend.respond((_) => FakeBackend.ok([]));

      await expectLater(repo.sendMood('c1', 'u1', MoodType.happy), throwsA(isA<EncryptionNotReady>()));

      expect(backend.requests, isEmpty, reason: 'nothing may be sent unencrypted');
      expect(local.outbox.pending, 0);
      expect(notifications.sent, isEmpty);
    });

    test('a custom mood carries its text and emoji', () async {
      backend.respond((_) => FakeBackend.ok([]));

      await repo.sendMood('c1', 'u1', MoodType.custom, custom: const CustomMood(label: 'Cozy', emoji: '🧸'));

      final request = backend.requests.first;
      final row = request.json as Map;
      expect(row.containsKey('custom_label'), isFalse);
      expect(row.containsKey('custom_emoji'), isFalse);
      expect(bodyText(request.json), isNot(contains('Cozy')), reason: 'a custom mood name must never be readable');
      final opened = await cipher.openJson(row['enc'] as String, coupleId: 'c1', table: 'moods', rowId: row['id'] as String);
      expect(opened['label'], 'Cozy');
      expect(opened['emoji'], '🧸');
      expect(notifications.sent.single.body, isNot(contains('Cozy')));
      expect(notifications.sent.single.detail, 'Alex is feeling Cozy 🧸');
    });

    test('an already-stored mood (duplicate key) counts as delivered and does not notify twice', () async {
      backend.respond((_) => FakeBackend.error('23505', 'duplicate key value'));

      final reachedServer = await repo.sendMood('c1', 'u1', MoodType.happy);

      expect(reachedServer, isTrue);
      expect(notifications.sent, isEmpty);
    });

    test('a rejected insert is reported to the caller, not queued', () async {
      backend.respond((_) => FakeBackend.error('42501', 'permission denied', status: 403));

      await expectLater(repo.sendMood('c1', 'u1', MoodType.happy), throwsA(anything));
      expect(local.outbox.pending, 0);
    });
  });

  group('reads', () {
    test('getLastSentMood asks for the newest mood of that user', () async {
      backend.respond((_) => FakeBackend.ok([
            {'type': 'sleeping', 'user_id': 'u1', 'sent_at': '2026-02-01T10:00:00Z'}
          ]));

      final mood = await repo.getLastSentMood('u1');

      final q = backend.requests.single.query;
      expect(q['user_id'], 'eq.u1');
      expect(q['order'], startsWith('sent_at.desc'));
      expect(q['limit'], '1');
      expect(mood?.type, MoodType.sleeping);
    });

    test('getLastSentMood is null when the user has never sent one', () async {
      backend.respond((_) => FakeBackend.ok([]));
      expect(await repo.getLastSentMood('u1'), isNull);
    });

    test('getMyCustomMoods removes repeats, skips empty labels, defaults the emoji and honours the limit', () async {
      Map<String, dynamic> legacy(String? label, String? emoji) =>
          {'type': 'custom', 'user_id': 'u1', 'sent_at': '2026-02-01T10:00:00Z', 'custom_label': label, 'custom_emoji': emoji};
      backend.respond((_) => FakeBackend.ok([
            legacy('Cozy', '🧸'),
            legacy('Cozy', '🧸'),
            legacy('', '❌'),
            legacy(null, '❌'),
            legacy('Calm', null),
            legacy('Hungry', '🍕'),
          ]));

      final moods = await repo.getMyCustomMoods('u1', limit: 2);

      expect(moods, [
        const CustomMood(label: 'Cozy', emoji: '🧸'),
        CustomMood(label: 'Calm', emoji: MoodType.custom.emoji),
      ]);
      expect(backend.requests.single.query['type'], 'eq.custom');
    });
  });

  group('reading sealed moods', () {
    Future<Map<String, dynamic>> sealedRow(String id, Map<String, dynamic> content, {String user = 'u1', ContentCipher? by}) async => {
          'id': id,
          'couple_id': 'c1',
          'user_id': user,
          'type': 'custom', // the placeholder every new mood carries
          'sent_at': '2026-02-01T10:00:00Z',
          'enc': await (by ?? cipher).sealJson(content, coupleId: 'c1', table: 'moods', rowId: id),
        };

    test('a sealed mood is opened, and an older readable one is still shown', () async {
      final sealed = await sealedRow('m1', {'type': 'sleeping', 'label': null, 'emoji': null});
      backend.respond((_) => FakeBackend.ok([
            sealed,
            {'id': 'm2', 'couple_id': 'c1', 'user_id': 'u2', 'type': 'happy', 'sent_at': '2026-02-01T11:00:00Z'},
          ]));

      final moods = await repo.getMoodsSince('c1', DateTime.utc(2026, 1, 1));

      expect(moods.map((m) => m.type), [MoodType.sleeping, MoodType.happy]);
    });

    test('a sealed custom mood comes back with its text', () async {
      final sealed = await sealedRow('m1', {'type': 'custom', 'label': 'Cozy', 'emoji': '🧸'});
      backend.respond((_) => FakeBackend.ok([sealed]));

      final mood = await repo.getLastSentMood('u1');

      expect(mood!.type, MoodType.custom);
      expect(mood.label, 'Cozy');
      expect(mood.emoji, '🧸');
    });

    test('custom moods are found by opening the sealed ones', () async {
      final rows = [
        await sealedRow('m1', {'type': 'custom', 'label': 'Cozy', 'emoji': '🧸'}),
        await sealedRow('m2', {'type': 'happy', 'label': null, 'emoji': null}), // a built-in: not a custom mood
        await sealedRow('m3', {'type': 'custom', 'label': 'Calm', 'emoji': null}),
      ];
      backend.respond((_) => FakeBackend.ok(rows));

      final customs = await repo.getMyCustomMoods('u1');

      expect(customs, [const CustomMood(label: 'Cozy', emoji: '🧸'), CustomMood(label: 'Calm', emoji: MoodType.custom.emoji)]);
    });

    test('a mood sealed with a different key is left out instead of shown wrong', () async {
      final strangers = await readyCipher();
      final foreign = await sealedRow('m1', {'type': 'happy', 'label': null, 'emoji': null}, by: strangers);
      final mine = await sealedRow('m2', {'type': 'busy', 'label': null, 'emoji': null});
      backend.respond((_) => FakeBackend.ok([foreign, mine]));

      final moods = await repo.getMoodsSince('c1', DateTime.utc(2026, 1, 1));

      expect(moods.map((m) => m.type), [MoodType.busy]);
    });

    test('a ciphertext moved to another row is left out', () async {
      final row = await sealedRow('m1', {'type': 'happy', 'label': null, 'emoji': null});
      backend.respond((_) => FakeBackend.ok([{...row, 'id': 'm-moved'}]));
      expect(await repo.getMoodsSince('c1', DateTime.utc(2026, 1, 1)), isEmpty);
    });

    test('without the couple key, sealed moods are simply not shown yet', () async {
      final row = await sealedRow('m1', {'type': 'happy', 'label': null, 'emoji': null});
      repo = MoodRepository(
        client: backend.client,
        notifications: notifications,
        outbox: local.outbox,
        sessionCache: local.sessionCache,
        cipher: notReadyCipher(),
      );
      backend.respond((_) => FakeBackend.ok([row]));
      expect(await repo.getMoodsSince('c1', DateTime.utc(2026, 1, 1)), isEmpty);
    });

    test('the copy saved on the phone stays sealed, and is opened when shown', () async {
      final row = await sealedRow('m1', {'type': 'missingYou', 'label': null, 'emoji': null});
      await local.sessionCache.put('moods:c1', [row]);

      final first = await repo.watchRecentMoods('c1').first;

      expect(first.single.type, MoodType.missingYou);
      expect(local.sessionCache.getList('moods:c1')!.single['enc'], row['enc'], reason: 'what is saved is still ciphertext');
    });
  });

  group('MoodModel', () {
    test('round-trips a custom mood through a row', () {
      final model = MoodModel(
        type: MoodType.custom,
        userId: 'u1',
        sentAt: DateTime.utc(2026, 3, 4, 5, 6),
        customLabel: 'Cozy',
        customEmoji: '🧸',
      );
      final row = model.toRow('c1');
      expect(row['sent_at'], '2026-03-04T05:06:00.000Z');
      final back = MoodModel.fromRow(row);
      expect(back.label, 'Cozy');
      expect(back.emoji, '🧸');
      expect(back.sentAt, model.sentAt);
    });

    test('an unknown stored type falls back to happy', () {
      expect(MoodType.fromString('somethingNew'), MoodType.happy);
    });
  });

  group('getMoodsSince', () {
    test('asks for the couple\'s moods since a time, oldest first', () async {
      backend.respond((_) => FakeBackend.ok([
            {'id': 'm1', 'couple_id': 'c1', 'user_id': 'u1', 'type': 'happy', 'sent_at': '2026-06-09T08:00:00+00:00'},
            {'id': 'm2', 'couple_id': 'c1', 'user_id': 'u2', 'type': 'custom', 'sent_at': '2026-06-09T09:00:00+00:00',
             'custom_label': 'Cozy', 'custom_emoji': '🧸'},
          ]));

      final moods = await repo.getMoodsSince('c1', DateTime.utc(2026, 6, 4));

      final req = backend.requests.single;
      expect(req.method, 'GET');
      expect(req.path, endsWith('/moods'));
      expect(req.query['couple_id'], 'eq.c1');
      expect(req.query['sent_at'], startsWith('gte.2026-06-04T00:00:00'));
      expect(req.query['order'], startsWith('sent_at.asc'));
      expect(req.query['limit'], isNotNull);
      expect(moods.map((m) => m.type), [MoodType.happy, MoodType.custom]);
      expect(moods.last.label, 'Cozy');
    });

    test('an offline error reaches the caller', () async {
      backend.respond((_) => FakeBackend.error('500', 'down', status: 500));
      await expectLater(repo.getMoodsSince('c1', DateTime.utc(2026, 6, 4)), throwsA(anything));
    });
  });
}
