import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/data/repositories/notification_repository.dart';
import 'package:usync/domain/entities/notification_item.dart';

import '../support/test_cipher.dart';
import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late ContentCipher cipher;
  late NotificationRepository repo;

  NotificationRepository build(ContentCipher c) => NotificationRepository(client: backend.client, cipher: c);

  /// The sender lookup is the only read notifyPartner makes; every other request is the insert.
  void serve() => backend.respond((req) =>
      req.path.endsWith('/profiles') ? FakeBackend.ok({'username': 'Alex'}) : FakeBackend.ok([], status: 201));

  Map<String, dynamic> insert() => backend.requests.firstWhere((r) => r.path.endsWith('/notifications')).json as Map<String, dynamic>;

  setUp(() async {
    backend = FakeBackend();
    cipher = await readyCipher();
    repo = build(cipher);
  });

  tearDown(() => backend.dispose());

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
      expect(row['body_text'], 'Alex shared a mood 💭');
      expect(row['detail_enc'], startsWith('u1:'));
      expect(bodyText(row), isNot(contains('Missing')));
      final opened = await cipher.openText(row['detail_enc'] as String, coupleId: 'c1', table: 'notifications', rowId: row['id'] as String, field: 'detail');
      expect(opened, 'Alex is feeling "Missing you terribly"');
    });

    test('a notification without a detail has no detail_enc', () async {
      serve();
      await repo.notifyPartner(coupleId: 'c1', fromUserId: 'u1', type: NotifType.touch, body: (n) => '$n is thinking of you');
      expect(insert().containsKey('detail_enc'), isFalse);
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
      expect(row['body_text'], 'Alex shared a mood 💭');
      expect(row.containsKey('detail_enc'), isFalse);
      expect(bodyText(row), isNot(contains('Missing')));
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

    test('without the couple key the fixed sentence is shown', () async {
      final sealed = await seal('n1', 'secret');
      repo = build(notReadyCipher());
      final rows = [await row('n1', 'Sam shared a mood 💭', detailEnc: sealed)];
      backend.respond((_) => FakeBackend.ok(rows));

      expect((await repo.getNotifications('c1')).single.bodyText, 'Sam shared a mood 💭');
    });
  });
}
