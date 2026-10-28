import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/data/repositories/milestone_repository.dart';
import 'package:usync/domain/entities/milestone.dart';
import 'package:usync/domain/entities/notification_item.dart';

import '../support/test_cipher.dart';
import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late LocalStorage local;
  late RecordingNotifications notifications;
  late ContentCipher cipher;
  late MilestoneRepository repo;

  MilestoneRepository build(ContentCipher c) => MilestoneRepository(
        client: backend.client,
        notifications: notifications,
        outbox: local.outbox,
        sessionCache: local.sessionCache,
        cipher: c,
      );

  setUp(() async {
    backend = FakeBackend();
    local = LocalStorage();
    await local.setUp();
    notifications = RecordingNotifications();
    cipher = await readyCipher();
    repo = build(cipher);
  });

  tearDown(() async {
    await local.tearDown();
    await backend.dispose();
  });

  group('addDate', () {
    test('sends the date only as ciphertext, with placeholders, and tells the partner without the words', () async {
      backend.respond((_) => FakeBackend.ok([], status: 201));

      final result = await repo.addDate(
        coupleId: 'c1', userId: 'u1', title: 'Our first kiss', date: DateTime(2026, 7, 14),
        note: 'under the umbrella', emoji: '💋', repeatsYearly: true,
      );

      expect(result.sentNow, isTrue);
      final insert = backend.requests.single;
      expect(insert.path, endsWith('/milestones'));
      final row = insert.json as Map<String, dynamic>;
      expect(row['id'], result.milestone.id);
      expect(row['type'], 'custom');
      expect(row['title'], '🔒');
      expect(row['repeats_yearly'], isFalse);
      expect(row['enc'], startsWith('u1:'));
      expect(row.containsKey('note'), isFalse);
      expect(row.containsKey('emoji'), isFalse);
      expect(row['occurred_at'], startsWith('1970-01-01'), reason: 'the real day is not readable');
      for (final secret in ['kiss', 'umbrella', '💋', '2026-07', '07-14']) {
        expect(bodyText(row), isNot(contains(secret)), reason: '"$secret" must not be readable');
      }

      final opened = await cipher.openJson(row['enc'] as String, coupleId: 'c1', table: 'milestones', rowId: result.milestone.id);
      expect(opened['title'], 'Our first kiss');
      expect(opened['note'], 'under the umbrella');
      expect(opened['repeatsYearly'], isTrue);
      expect(DateTime.parse(opened['occurredAt'] as String), DateTime.utc(2026, 7, 14, 12));

      expect(notifications.sent.single.type, NotifType.milestone);
      expect(notifications.sent.single.body, 'Alex added a date to your timeline 🕰️');
      expect(notifications.sent.single.detail, contains('Our first kiss'));
    });

    test('without the couple key nothing is sent or queued, and the caller is told', () async {
      repo = build(notReadyCipher());
      backend.respond((_) => FakeBackend.ok([]));

      await expectLater(
        repo.addDate(coupleId: 'c1', userId: 'u1', title: 't', date: DateTime(2026), emoji: '✨', repeatsYearly: false),
        throwsA(isA<EncryptionNotReady>()),
      );

      expect(backend.requests, isEmpty);
      expect(local.outbox.pending, 0);
    });
  });

  group('getMilestones', () {
    Future<Map<String, dynamic>> sealedRow(String id, {ContentCipher? by, String title = 'Anniversary'}) async => {
          'id': id,
          'couple_id': 'c1',
          'type': 'custom',
          'title': '🔒',
          'occurred_at': '1970-01-01T12:00:00Z',
          'note': null,
          'linked_memory_id': null,
          'emoji': null,
          'repeats_yearly': false,
          'enc': await (by ?? cipher).sealJson(
            {'title': title, 'note': 'n', 'emoji': '🎂', 'repeatsYearly': true, 'occurredAt': '2024-05-06T12:00:00.000Z'},
            coupleId: 'c1', table: 'milestones', rowId: id,
          ),
        };

    Map<String, dynamic> readable(String id, String type, String title, String at) => {
          'id': id, 'couple_id': 'c1', 'type': type, 'title': title, 'occurred_at': at,
          'note': null, 'linked_memory_id': null, 'emoji': null, 'repeats_yearly': false, 'enc': null,
        };

    Future<List<Milestone>> load(List<Map<String, dynamic>> rows, {ContentCipher? as}) {
      if (as != null) repo = build(as);
      backend.respond((_) => FakeBackend.ok(rows));
      return repo.getMilestones('c1');
    }

    test('a sealed date is opened, and readable ones (older dates, server milestones) are kept', () async {
      final milestones = await load([
        await sealedRow('m1'),
        readable('m2', 'custom', 'Old readable date', '2025-01-01T12:00:00Z'),
        readable('m3', 'streak7', '7-day streak achieved', '2026-02-02T12:00:00Z'),
      ]);

      expect(milestones.map((m) => m.title), ['Anniversary', 'Old readable date', '7-day streak achieved']);
      final first = milestones.first;
      expect(first.note, 'n');
      expect(first.displayEmoji, '🎂');
      expect(first.repeatsYearly, isTrue);
      expect(first.occurredAt, DateTime.utc(2024, 5, 6, 12));
      expect(milestones[2].type, MilestoneType.streak7);
    });

    test('a date this phone cannot open shows as locked instead of disappearing', () async {
      final milestones = await load([await sealedRow('m1', by: await readyCipher())]);
      expect(milestones, hasLength(1));
      expect(milestones.single.title, isNot('Anniversary'));
      expect(milestones.single.displayEmoji, '🔒');
    });

    test('without the couple key sealed dates show as locked', () async {
      final milestones = await load([await sealedRow('m1')], as: notReadyCipher());
      expect(milestones.single.title, isNot('Anniversary'));
    });

    test('a date copied onto another row does not open', () async {
      final row = await sealedRow('m1');
      final milestones = await load([{...row, 'id': 'm-other'}]);
      expect(milestones.single.title, isNot('Anniversary'));
    });

    test('the copy kept for offline use stays sealed', () async {
      final row = await sealedRow('m1');
      await load([row]);
      final cached = local.sessionCache.getList('milestones:c1')!;
      expect(cached.single['enc'], row['enc']);
      expect(bodyText(cached), isNot(contains('Anniversary')));
    });
  });
}
