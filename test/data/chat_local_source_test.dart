import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:usync/data/datasources/local/chat_local_source.dart';

Map<String, dynamic> _m(String id, int at, {bool mine = false, int? seen, int? exp, String text = 'x'}) => {
      'id': id, 'at': at, 'mine': mine, 't': text, if (seen != null) 'seen': seen, if (exp != null) 'exp': exp,
    };

void main() {
  late Directory dir;
  late ChatLocalSource source;
  var n = 0;

  Future<ChatLocalSource> open() async {
    final i = n;
    return ChatLocalSource(
      messages: await Hive.openLazyBox<dynamic>('m$i'),
      index: await Hive.openBox<dynamic>('i$i'),
      media: await Hive.openLazyBox<dynamic>('b$i'),
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chat_local');
    Hive.init(dir.path);
    n++;
    source = await open();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('a page is the newest messages in order; older ones come with `before`', () async {
    for (var i = 1; i <= 10; i++) {
      await source.put(_m('m$i', i * 1000000000000));
    }
    final newest = await source.page(limit: 4);
    expect(newest.map((m) => m['id']), ['m7', 'm8', 'm9', 'm10']);
    final older = await source.page(before: newest.first['at'] as int, limit: 4);
    expect(older.map((m) => m['id']), ['m3', 'm4', 'm5', 'm6']);
    expect(source.hasOlderThan(older.first['at'] as int), isTrue);
    expect(source.hasOlderThan(1000000000000), isFalse);
  });

  test('messages sent in the same microsecond both stay, in the order they came', () async {
    await source.put(_m('a', 5000000));
    await source.put(_m('b', 5000000));
    expect((await source.page(limit: 5)).map((m) => m['id']), ['a', 'b']);
    // Updating one does not duplicate or lose either.
    await source.update('b', (m) => {...m, 't': 'changed'});
    expect((await source.page(limit: 5)).map((m) => m['t']), ['x', 'changed']);
  });

  test('changing a message\'s time moves it', () async {
    await source.put(_m('a', 1000));
    await source.put(_m('b', 2000));
    await source.update('a', (m) => {...m, 'at': 3000});
    expect((await source.page(limit: 5)).map((m) => m['id']), ['b', 'a']);
  });

  test('unread counts only the partner\'s unread messages, and drops when they are read', () async {
    await source.put(_m('1', 1));
    await source.put(_m('2', 2));
    await source.put(_m('3', 3, mine: true));
    await source.put(_m('4', 4, seen: 99));
    expect(source.unreadCount, 2);
    await source.update('1', (m) => {...m, 'seen': 5});
    expect(source.unreadCount, 1);
  });

  test('expired ids are those whose time has come', () async {
    final now = DateTime.utc(2026, 6, 1, 12);
    await source.put(_m('gone', 1, exp: now.subtract(const Duration(seconds: 1)).microsecondsSinceEpoch));
    await source.put(_m('later', 2, exp: now.add(const Duration(minutes: 1)).microsecondsSinceEpoch));
    await source.put(_m('never', 3));
    expect(source.expiredIds(now), ['gone']);
  });

  test('deleting removes the message and its media; clearing removes everything but keeps the owner', () async {
    await source.claim('u:c');
    await source.put(_m('a', 1), media: Uint8List.fromList([1, 2, 3]));
    await source.put(_m('b', 2));
    expect(await source.mediaBytes('a'), [1, 2, 3]);

    await source.delete(['a']);
    expect(source.has('a'), isFalse);
    expect(await source.mediaBytes('a'), isNull);
    expect(await source.page(limit: 5), hasLength(1));

    await source.clear();
    expect(await source.page(limit: 5), isEmpty);
    expect(source.owner, 'u:c');
    await source.reset();
    expect(source.owner, isNull);
  });

  test('another account\'s history is thrown away when the phone is claimed', () async {
    expect(await source.claim('a:c1'), isTrue);
    await source.put(_m('a', 1));
    expect(await source.claim('a:c1'), isFalse);
    expect(source.has('a'), isTrue);

    expect(await source.claim('b:c1'), isTrue);
    expect(source.has('a'), isFalse);
  });

  test('the history survives closing and opening the boxes again', () async {
    await source.put(_m('a', 1000, text: 'kept'), media: Uint8List.fromList([9]));
    await Hive.close();
    Hive.init(dir.path);
    final again = await open();
    expect((await again.get('a'))!['t'], 'kept');
    expect(await again.mediaBytes('a'), [9]);
    expect((await again.page(limit: 5)).single['id'], 'a');
  });

  test('a deleted message is remembered, so it is not taken for new', () async {
    await source.put(_m('a', 1));
    expect(source.knows('a'), isTrue);
    await source.delete(['a']);
    expect(source.has('a'), isFalse);
    expect(source.knows('a'), isTrue);
    expect(source.knows('never'), isFalse);
    await source.clear();
    expect(source.knows('a'), isFalse);
  });

  test('concurrent updates of one message do not lose each other\'s change', () async {
    await source.put(_m('a', 1));
    await Future.wait([
      source.update('a', (m) => {...m, 'x': 1}),
      source.update('a', (m) => {...m, 'y': 2}),
      source.update('a', (m) => {...m, 'z': 3}),
    ]);
    final m = (await source.get('a'))!;
    expect([m['x'], m['y'], m['z']], [1, 2, 3]);
  });

  test('ids at or before a time', () async {
    await source.put(_m('a', 100));
    await source.put(_m('b', 200));
    await source.put(_m('c', 300));
    expect(source.idsAtOrBefore(200)..sort(), ['a', 'b']);
  });

  test('a thousand messages: a page is read without reading them all', () async {
    for (var i = 0; i < 1000; i++) {
      await source.put(_m('m$i', 1000 + i));
    }
    expect(source.count, 1000);
    final sw = Stopwatch()..start();
    final page = await source.page(limit: 30);
    sw.stop();
    expect(page.length, 30);
    expect(page.last['id'], 'm999');
    expect(sw.elapsedMilliseconds, lessThan(500));
  });
}
