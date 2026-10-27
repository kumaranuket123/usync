import 'package:flutter_test/flutter_test.dart';
import 'package:usync/data/repositories/bucket_repository.dart';
import 'package:usync/domain/entities/bucket_item.dart';
import 'package:usync/domain/entities/notification_item.dart';

import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late LocalStorage local;
  late RecordingNotifications notifications;
  late BucketRepository repo;

  setUp(() async {
    backend = FakeBackend();
    local = LocalStorage();
    await local.setUp();
    notifications = RecordingNotifications();
    repo = BucketRepository(
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

  BucketItem item({bool done = false}) => BucketItem(
        id: 'i1',
        coupleId: 'c1',
        title: 'Watch the sunrise',
        emoji: '🏔️',
        createdAt: DateTime(2026),
        doneAt: done ? DateTime(2026, 2) : null,
      );

  group('addItem', () {
    test('inserts with a client-chosen id, only the allowed columns, and notifies the partner', () async {
      backend.respond((_) => FakeBackend.ok([]));

      final result = await repo.addItem(
        coupleId: 'c1', userId: 'u1', title: 'Watch the sunrise', emoji: '🏔️', note: 'Nandi Hills',
      );

      expect(result.sentNow, isTrue);
      final insert = backend.requests.single;
      expect(insert.method, 'POST');
      expect(insert.path, endsWith('/bucket_items'));
      final row = insert.json as Map;
      expect(row['id'], result.item.id);
      expect(row['couple_id'], 'c1');
      expect(row['created_by'], 'u1');
      expect(row['title'], 'Watch the sunrise');
      expect(row['note'], 'Nandi Hills');
      expect(row.containsKey('done_at'), isFalse, reason: 'a new item can never start ticked off');
      expect(row.containsKey('done_by'), isFalse);

      final note = notifications.sent.single;
      expect(note.type, NotifType.milestone);
      expect(note.body, 'Alex added "Watch the sunrise" to your bucket list 🏔️');
    });

    test('an item that already reached the server is not added twice', () async {
      backend.respond((_) => FakeBackend.error('23505', 'duplicate key value'));

      final result = await repo.addItem(coupleId: 'c1', userId: 'u1', title: 'Hike', emoji: '✨');

      expect(result.sentNow, isTrue);
      expect(notifications.sent, isEmpty);
    });
  });

  group('setDone', () {
    test('ticks through the RPC and tells the partner', () async {
      backend.respond((_) => FakeBackend.ok(null, status: 204));

      await repo.setDone(coupleId: 'c1', userId: 'u1', item: item(), done: true);

      final rpc = backend.requests.single;
      expect(rpc.path, endsWith('/rpc/set_bucket_item_done'));
      expect(rpc.json, {'p_item': 'i1', 'p_done': true});
      expect(notifications.sent.single.body, 'Alex checked off "Watch the sunrise" 🎉');
    });

    test('un-ticking does not notify the partner', () async {
      backend.respond((_) => FakeBackend.ok(null, status: 204));

      await repo.setDone(coupleId: 'c1', userId: 'u1', item: item(done: true), done: false);

      expect(backend.requests.single.json, {'p_item': 'i1', 'p_done': false});
      expect(notifications.sent, isEmpty);
    });
  });

  test('deleteItem removes the row by id', () async {
    backend.respond((_) => FakeBackend.ok([]));

    await repo.deleteItem('i1');

    final req = backend.requests.single;
    expect(req.method, 'DELETE');
    expect(req.path, endsWith('/bucket_items'));
    expect(req.query['id'], 'eq.i1');
  });
}
