import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:usync/data/datasources/local/protected_boxes.dart';

void main() {
  late Directory dir;
  final cipher = HiveAesCipher(List<int>.generate(32, (i) => i + 1));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('protected_boxes');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  /// Everything the box wrote to disk, as text, to look for readable content.
  String onDisk(String name) => File('${dir.path}/${name.toLowerCase()}.hive').readAsBytesSync().map(String.fromCharCode).join();

  test('what is stored is encrypted on disk and reads back', () async {
    final box = await openProtectedBox('cache_enc', cipher);
    await box.put('profile', '{"name":"Alexandria Secretname"}');
    await box.close();

    expect(onDisk('cache_enc'), isNot(contains('Secretname')), reason: 'values are encrypted (the key names are not)');

    final again = await openProtectedBox('cache_enc', cipher);
    expect(again.get('profile'), '{"name":"Alexandria Secretname"}');
  });

  test('an older unencrypted box is copied over once and its file is deleted', () async {
    final legacy = await Hive.openBox<dynamic>('outbox');
    await legacy.add({'type': 'note', 'text': 'queued secret'});
    await legacy.add({'type': 'note', 'text': 'second'});
    await legacy.close();
    expect(onDisk('outbox'), contains('queued secret'), reason: 'the old file really was readable');

    final box = await openProtectedBox('outbox_enc', cipher, legacyName: 'outbox');

    expect(box.length, 2);
    expect(box.values.map((e) => (e as Map)['text']), ['queued secret', 'second']);
    expect(await Hive.boxExists('outbox'), isFalse);
    expect(onDisk('outbox_enc'), isNot(contains('queued secret')));

    // New entries continue after the copied ones.
    await box.add({'type': 'note', 'text': 'third'});
    expect(box.length, 3);
  });

  test('an interrupted migration does not repeat entries', () async {
    // The copy happened but the old file was not deleted yet.
    final target = await openProtectedBox('outbox_enc', cipher);
    await target.add({'text': 'already copied'});
    await target.close();
    final legacy = await Hive.openBox<dynamic>('outbox');
    await legacy.add({'text': 'already copied'});
    await legacy.close();

    final box = await openProtectedBox('outbox_enc', cipher, legacyName: 'outbox');

    expect(box.length, 1);
    expect(await Hive.boxExists('outbox'), isFalse);
  });

  test('without an old box nothing is created or copied', () async {
    final box = await openProtectedBox('cache_enc', cipher, legacyName: 'cache');
    expect(box.isEmpty, isTrue);
    expect(await Hive.boxExists('cache'), isFalse);
  });

  test('a box the key cannot open is discarded and started empty', () async {
    final box = await openProtectedBox('cache_enc', cipher);
    await box.put('k', 'v');
    await box.close();

    final otherKey = HiveAesCipher(List<int>.generate(32, (i) => 200 - i));
    final reopened = await openProtectedBox('cache_enc', otherKey);

    expect(reopened.isEmpty, isTrue);
    await reopened.put('k2', 'v2');
    expect(reopened.get('k2'), 'v2');
  });
}
