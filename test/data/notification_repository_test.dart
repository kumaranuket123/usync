import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/data/datasources/local/notification_local_source.dart';
import 'package:usync/data/repositories/notification_repository.dart';
import 'package:usync/domain/entities/notification_item.dart';

import '../support/test_cipher.dart';
import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late ContentCipher cipher;
  late NotificationRepository repo;

  late NotificationLocalSource local;
  late Directory dir;
  var boxN = 0;

  NotificationRepository build(ContentCipher c) =>
      NotificationRepository(client: backend.client, cipher: c, localSource: local);

  /// The sender lookup is the only read notifyPartner makes; every other request is the insert.
  void serve() => backend.respond((req) =>
      req.path.endsWith('/profiles') ? FakeBackend.ok({'username': 'Alex'}) : FakeBackend.ok([], status: 201));

  Map<String, dynamic> insert() => backend.requests.firstWhere((r) => r.path.endsWith('/notifications')).json as Map<String, dynamic>;

  setUp(() async {
    backend = FakeBackend();
    cipher = await readyCipher();
    dir = Directory.systemTemp.createTempSync('notif_test');
    Hive.init(dir.path);
    local = NotificationLocalSource(box: await Hive.openBox<dynamic>('n${boxN++}'));
    repo = build(cipher);
  });

  tearDown(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
    await backend.dispose();
  });

  group('notifyPartner', () {
    test('the row holds a fixed sentence, and the detail only as ciphertext bound to the row', () async {
      serve();

      await repo.notifyPartner(
        coupleId: 'c1',
        fromUserId: 'u1',
        type: NotifType.milestone,
        body: (n) => '$n shared a mood 💭',
        detail: (n) => '$n is feeling "Missing you terribly"',
      );

      final row = insert();
      expect(row['body_text'], 'Your partner shared a mood 💭');
      expect(row['detail_enc'], startsWith('u1:'));
      expect(bodyText(row), isNot(contains('Missing')));
      final opened = await cipher.openText(row['detail_enc'] as String, coupleId: 'c1', table: 'notifications', rowId: row['id'] as String, field: 'detail');
      expect(opened, 'Alex is feeling "Missing you terribly"');
    });

    test('the sender\'s name is never in the stored row: the nameless sentence is stored and the named one sealed', () async {
      serve();
      await repo.notifyPartner(coupleId: 'c1', fromUserId: 'u1', type: NotifType.touch, body: (n) => '$n wants to feel you 💞');

      final row = insert();
      expect(row['body_text'], 'Your partner wants to feel you 💞');
      expect(bodyText(row), isNot(contains('Alex')));
      expect(row['detail_enc'], startsWith('u1:'));
      final opened = await cipher.openText(row['detail_enc'] as String, coupleId: 'c1', table: 'notifications', rowId: row['id'] as String, field: 'detail');
      expect(opened, 'Alex wants to feel you 💞', reason: 'the app shows the named sentence after opening it');
    });

    test('a typed detail stays sealed and the name stays out of body_text', () async {
      serve();
      await repo.notifyPartner(coupleId: 'c1', fromUserId: 'u1', type: NotifType.moodChange, body: (n) => '$n shared a mood 💭', detail: (n) => '$n is feeling "Calm"');

      final row = insert();
      expect(bodyText(row), isNot(contains('Alex')));
      expect(bodyText(row), isNot(contains('Calm')));
    });

    test('without the couple key the partner still gets the fixed sentence, never the detail in the clear', () async {
      repo = build(notReadyCipher());
      serve();

      await repo.notifyPartner(
        coupleId: 'c1',
        fromUserId: 'u1',
        type: NotifType.milestone,
        body: (n) => '$n shared a mood 💭',
        detail: (n) => '$n is feeling "Missing you terribly"',
      );

      final row = insert();
      expect(row['body_text'], 'Your partner shared a mood 💭');
      expect(row.containsKey('detail_enc'), isFalse);
      expect(bodyText(row), isNot(contains('Missing')));
      expect(bodyText(row), isNot(contains('Alex')));
    });
  });

  group('reading', () {
    Future<Map<String, dynamic>> row(String id, String body, {String? detailEnc, String type = 'milestone'}) async => {
          'id': id,
          'couple_id': 'c1',
          'from_user_id': 'u2',
          'type': type,
          'body_text': body,
          'detail_enc': detailEnc,
          'is_read': false,
          'created_at': '2026-03-01T10:00:00Z',
        };

    Future<String> seal(String id, String text, {ContentCipher? by, String coupleId = 'c1'}) =>
        (by ?? cipher).sealText(text, coupleId: coupleId, table: 'notifications', rowId: id, field: 'detail');

    test('the decrypted detail replaces the fixed sentence, and an older row keeps its text', () async {
      final rows = [
        await row('n1', 'Sam shared a mood 💭', detailEnc: await seal('n1', 'Sam is feeling "Calm"')),
        {...await row('n2', 'Sam added "Old" to your bucket list'), 'created_at': '2026-02-01T10:00:00Z'},
      ];
      backend.respond((_) => FakeBackend.ok(rows));

      final items = await repo.getNotifications('c1');

      expect(items.map((i) => i.bodyText), ['Sam is feeling "Calm"', 'Sam added "Old" to your bucket list']);
    });

    test('a detail this phone cannot open falls back to the fixed sentence', () async {
      final foreign = await seal('n1', 'secret', by: await readyCipher());
      final rows = [await row('n1', 'Sam shared a mood 💭', detailEnc: foreign)];
      backend.respond((_) => FakeBackend.ok(rows));

      final items = await repo.getNotifications('c1');

      expect(items.single.bodyText, 'Sam shared a mood 💭');
    });

    test('a detail moved onto another notification does not open', () async {
      final other = await seal('n-other', 'secret');
      final rows = [await row('n1', 'Sam shared a mood 💭', detailEnc: other)];
      backend.respond((_) => FakeBackend.ok(rows));

      expect((await repo.getNotifications('c1')).single.bodyText, 'Sam shared a mood 💭');
    });

    test('without the couple key it waits: nothing is saved and the server row is not deleted', () async {
      final sealed = await seal('n1', 'secret');
      repo = build(notReadyCipher());
      final rows = [await row('n1', 'Sam shared a mood 💭', detailEnc: sealed)];
      backend.respond((_) => FakeBackend.ok(rows));

      expect(await repo.getNotifications('c1'), isEmpty);
      expect(backend.requests.where((r) => r.path.contains('ack_notifications')), isEmpty);
    });

    test('collected notifications are saved on the phone and deleted from the server', () async {
      final rows = [await row('n1', 'Sam shared a mood 💭')];
      backend.respond((req) => req.path.contains('ack_notifications') ? FakeBackend.ok(null, status: 204) : FakeBackend.ok(rows));

      await repo.collect();

      expect(local.has('n1'), isTrue);
      final ack = backend.requests.firstWhere((r) => r.path.contains('ack_notifications'));
      expect((ack.json as Map)['p_ids'], ['n1']);
    });

    test('read state is kept on the phone only and survives the next collection', () async {
      final rows = [await row('n1', 'Sam shared a mood 💭')];
      backend.respond((req) => req.path.contains('ack_notifications') ? FakeBackend.ok(null, status: 204) : FakeBackend.ok(rows));
      await repo.collect();

      await repo.markRead('c1', 'n1');
      await repo.collect(); // the server still had the row (the delete failed): it must not turn unread again

      expect((await repo.getNotifications('c1')).single.isRead, isTrue);
      expect(backend.requests.where((r) => r.method == 'PATCH'), isEmpty);
    });

    test('only the newest touch from the same person is kept', () async {
      final rows = [
        {...await row('t1', 'Sam touched you', type: 'touch'), 'created_at': '2026-03-01T10:00:00Z'},
        {...await row('t2', 'Sam touched you', type: 'touch'), 'created_at': '2026-03-01T11:00:00Z'},
      ];
      backend.respond((req) => req.path.contains('ack_notifications') ? FakeBackend.ok(null, status: 204) : FakeBackend.ok(rows));

      final items = await repo.getNotifications('c1');

      expect(items.map((i) => i.id), ['t2']);
    });
  });
}
