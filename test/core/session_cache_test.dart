import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:usync/data/datasources/local/session_cache.dart';

void main() {
  late Directory dir;
  late SessionCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cache_test');
    Hive.init(dir.path);
    cache = SessionCache(box: await Hive.openBox<dynamic>('c_${DateTime.now().microsecondsSinceEpoch}'));
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('a row comes back as it was saved', () async {
    await cache.put(SessionCache.profile('u1'), {'id': 'u1', 'username': 'gf', 'couple_id': null});
    expect(cache.getMap(SessionCache.profile('u1')), {'id': 'u1', 'username': 'gf', 'couple_id': null});
  });

  test('a list of rows comes back in order', () async {
    await cache.put(SessionCache.moods('c1'), [
      {'type': 'happy', 'sent_at': '2026-10-25T10:00:00Z'},
      {'type': 'custom', 'custom_label': 'Craving pizza'},
    ]);
    final rows = cache.getList(SessionCache.moods('c1'))!;
    expect(rows.map((r) => r['type']), ['happy', 'custom']);
  });

  test('missing keys give null, and clear removes everything', () async {
    expect(cache.getMap('nope'), isNull);
    expect(cache.getList('nope'), isNull);
    await cache.put(SessionCache.couple('c1'), {'id': 'c1'});
    await cache.clear();
    expect(cache.getMap(SessionCache.couple('c1')), isNull);
  });
}
