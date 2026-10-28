import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/data/repositories/bucket_repository.dart';
import 'package:usync/domain/entities/bucket_item.dart';
import 'package:usync/domain/entities/notification_item.dart';

import '../support/test_cipher.dart';
import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late LocalStorage local;
  late RecordingNotifications notifications;
  late BucketRepository repo;
  late ContentCipher cipher;

  setUp(() async {
    backend = FakeBackend();
    local = LocalStorage();
    await local.setUp();
    notifications = RecordingNotifications();
    cipher = await readyCipher();
    repo = BucketRepository(
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

  BucketItem item({bool done = false}) => BucketItem(
        id: 'i1',
        coupleId: 'c1',
        title: 'Watch the sunrise',
        emoji: '🏔️',
        createdAt: DateTime(2026),
        doneAt: done ? DateTime(2026, 2) : null,
      );

  group('addItem', () {
    test('sends the text only as ciphertext, with a client-chosen id, and notifies the partner without the words', () async {
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
      expect(row['title'], '🔒', reason: 'only a placeholder');
      expect(row['enc'], startsWith('u1:'));
      expect(row.containsKey('note'), isFalse);
      for (final secret in ['sunrise', 'Nandi', '🏔️']) {
        expect(bodyText(insert.json), isNot(contains(secret)), reason: '"$secret" must not be readable in the request');
      }
      final opened = await cipher.openJson(row['enc'] as String, coupleId: 'c1', table: 'bucket_items', rowId: result.item.id);
      expect(opened, {'title': 'Watch the sunrise', 'emoji': '🏔️', 'note': 'Nandi Hills'});
      expect(row.containsKey('done_at'), isFalse, reason: 'a new item can never start ticked off');
      expect(row.containsKey('done_by'), isFalse);

      final note = notifications.sent.single;
      expect(note.type, NotifType.milestone);
      expect(note.body, 'Alex added something to your bucket list 🎯');
      expect(note.detail, 'Alex added "Watch the sunrise" to your bucket list 🏔️');
    });

    test('without the couple key nothing is sent or queued, and the caller is told', () async {
      repo = BucketRepository(
        client: backend.client,
        notifications: notifications,
        outbox: local.outbox,
        sessionCache: local.sessionCache,
        cipher: notReadyCipher(),
      );
      backend.respond((_) => FakeBackend.ok([]));

      await expectLater(
        repo.addItem(coupleId: 'c1', userId: 'u1', title: 'Hike', emoji: '✨'),
        throwsA(isA<EncryptionNotReady>()),
      );

      expect(backend.requests, isEmpty);
      expect(local.outbox.pending, 0);
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
      expect(notifications.sent.single.body, 'Alex checked something off your bucket list 🎉');
      expect(notifications.sent.single.detail, 'Alex checked off "Watch the sunrise" 🎉');
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

  group('reading sealed items', () {
    Future<Map<String, dynamic>> sealedRow(String id, Map<String, dynamic> content, {ContentCipher? by}) async => {
          'id': id,
          'couple_id': 'c1',
          'title': '🔒',
          'emoji': '🔒',
          'note': null,
          'created_by': 'u1',
          'created_at': '2026-02-01T10:00:00Z',
          'done_at': null,
          'done_by': null,
          'enc': await (by ?? cipher).sealJson(content, coupleId: 'c1', table: 'bucket_items', rowId: id),
        };

    // The saved copy is the first thing the list shows, so it exercises the read path.
    Future<List<BucketItem>> shown(List<Map<String, dynamic>> rows, {ContentCipher? as}) async {
      final reader = BucketRepository(
        client: backend.client,
        notifications: notifications,
        outbox: local.outbox,
        sessionCache: local.sessionCache,
        cipher: as ?? cipher,
      );
      await local.sessionCache.put('bucket:c1', rows);
      return reader.watchItems('c1').first;
    }

    test('a sealed item is opened, and an older readable one is still shown', () async {
      final sealed = await sealedRow('i1', {'title': 'Paris', 'emoji': '✈️', 'note': 'in spring'});
      final legacy = {...sealed, 'id': 'i2', 'title': 'Old readable', 'emoji': '🎯', 'enc': null};

      final items = await shown([sealed, legacy]);

      expect(items.map((i) => i.title), ['Paris', 'Old readable']);
      expect(items.first.emoji, '✈️');
      expect(items.first.note, 'in spring');
    });

    test('an item this phone cannot open shows as locked instead of disappearing', () async {
      final foreign = await sealedRow('i1', {'title': 'Secret', 'emoji': '🤫', 'note': null}, by: await readyCipher());
      final items = await shown([foreign]);
      expect(items, hasLength(1));
      expect(items.single.title, isNot('Secret'));
      expect(items.single.emoji, '🔒');
    });

    test('without the couple key sealed items show as locked', () async {
      final sealed = await sealedRow('i1', {'title': 'Paris', 'emoji': '✈️', 'note': null});
      final items = await shown([sealed], as: notReadyCipher());
      expect(items.single.title, isNot('Paris'));
    });

    test('an item copied onto another row does not open', () async {
      final sealed = await sealedRow('i1', {'title': 'Paris', 'emoji': '✈️', 'note': null});
      final items = await shown([{...sealed, 'id': 'i-other'}]);
      expect(items.single.title, isNot('Paris'));
    });
  });
}
