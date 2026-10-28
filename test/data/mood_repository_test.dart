import 'package:flutter_test/flutter_test.dart';
import 'package:usync/data/models/mood_model.dart';
import 'package:usync/data/repositories/mood_repository.dart';
import 'package:usync/domain/entities/mood.dart';
import 'package:usync/domain/entities/notification_item.dart';

import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late LocalStorage local;
  late RecordingNotifications notifications;
  late MoodRepository repo;

  setUp(() async {
    backend = FakeBackend();
    local = LocalStorage();
    await local.setUp();
    notifications = RecordingNotifications();
    repo = MoodRepository(
      client: backend.client,
      notifications: notifications,
      outbox: local.outbox,
      sessionCache: local.sessionCache,
    );
  });

  tearDown(() async {
    await local.tearDown();
    await backend.dispose();
  });

  group('sendMood', () {
    test('inserts the mood with a client-chosen id and notifies the partner', () async {
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
      expect(row['type'], 'missingYou');
      expect(row.containsKey('custom_label'), isFalse, reason: 'built-in moods never send custom columns');

      final note = notifications.sent.single;
      expect(note.type, NotifType.moodChange);
      expect(note.fromUserId, 'u1');
      expect(note.body, 'Alex is feeling Missing You 💖');
    });

    test('a custom mood carries its text and emoji', () async {
      backend.respond((_) => FakeBackend.ok([]));

      await repo.sendMood('c1', 'u1', MoodType.custom, custom: const CustomMood(label: 'Cozy', emoji: '🧸'));

      final row = backend.requests.first.json as Map;
      expect(row['custom_label'], 'Cozy');
      expect(row['custom_emoji'], '🧸');
      expect(notifications.sent.single.body, 'Alex is feeling Cozy 🧸');
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
      backend.respond((_) => FakeBackend.ok([
            {'custom_label': 'Cozy', 'custom_emoji': '🧸'},
            {'custom_label': 'Cozy', 'custom_emoji': '🧸'},
            {'custom_label': '', 'custom_emoji': '❌'},
            {'custom_label': null, 'custom_emoji': '❌'},
            {'custom_label': 'Calm', 'custom_emoji': null},
            {'custom_label': 'Hungry', 'custom_emoji': '🍕'},
          ]));

      final moods = await repo.getMyCustomMoods('u1', limit: 2);

      expect(moods, [
        const CustomMood(label: 'Cozy', emoji: '🧸'),
        CustomMood(label: 'Calm', emoji: MoodType.custom.emoji),
      ]);
      expect(backend.requests.single.query['type'], 'eq.custom');
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
