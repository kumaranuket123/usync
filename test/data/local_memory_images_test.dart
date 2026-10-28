import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/device_key.dart';
import 'package:usync/data/datasources/local/local_memory_images.dart';

import '../support/in_memory_key_store.dart';

void main() {
  late Directory dir;
  late DeviceKey key;
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...'secret doodle pixels'.codeUnits]);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('local_images');
    key = DeviceKey(store: InMemoryKeyStore());
    LocalMemoryImages.configure(key);
    LocalMemoryImages.rootProvider = () async => dir;
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  File file(String id) => File('${dir.path}/$id.png');
  bool hasText(Uint8List b, String t) => String.fromCharCodes(b).contains(t);

  test('a saved picture is encrypted on disk and reads back', () async {
    await LocalMemoryImages.write('m1', png);

    final raw = file('m1').readAsBytesSync();
    expect(raw.take(4), isNot([0x89, 0x50, 0x4E, 0x47]), reason: 'not a PNG on disk');
    expect(hasText(raw, 'secret doodle'), isFalse);
    expect(await LocalMemoryImages.read('m1'), png);
    expect(await LocalMemoryImages.pathIfExists('m1'), file('m1').path);
    expect(await LocalMemoryImages.ids(), {'m1'});
  });

  test('a picture left readable by an earlier version is still shown, and sealed on first use', () async {
    file('old').writeAsBytesSync(png);

    expect(await LocalMemoryImages.read('old'), png);

    expect(hasText(file('old').readAsBytesSync(), 'secret doodle'), isFalse, reason: 'sealed after being read');
    expect(await LocalMemoryImages.read('old'), png);
  });

  test('sealLegacy seals every readable picture and leaves sealed ones alone', () async {
    file('a').writeAsBytesSync(png);
    await LocalMemoryImages.write('b', png);
    final before = file('b').readAsBytesSync();

    await LocalMemoryImages.sealLegacy();

    expect(hasText(file('a').readAsBytesSync(), 'secret doodle'), isFalse);
    expect(file('b').readAsBytesSync(), before);
    expect(await LocalMemoryImages.read('a'), png);
  });

  test('a file swapped onto another memory, or changed, does not open', () async {
    await LocalMemoryImages.write('m1', png);
    file('m1').copySync(file('m2').path);
    expect(await LocalMemoryImages.read('m2'), isNull);

    final raw = file('m1').readAsBytesSync();
    raw[raw.length - 1] ^= 1;
    file('m1').writeAsBytesSync(raw);
    expect(await LocalMemoryImages.read('m1'), isNull);
  });

  test('a picture from another phone (another key) does not open', () async {
    await LocalMemoryImages.write('m1', png);
    LocalMemoryImages.configure(DeviceKey(store: InMemoryKeyStore()));
    expect(await LocalMemoryImages.read('m1'), isNull);
  });

  test('a readable copy exists only while it is needed', () async {
    await LocalMemoryImages.write('m1', png);
    String? seen;

    final result = await LocalMemoryImages.withPlainCopy('m1', (path) async {
      seen = path;
      expect(File(path).readAsBytesSync(), png);
      expect(await LocalMemoryImages.ids(), {'m1'}, reason: 'the copy is not mistaken for a saved picture');
      return 'done';
    });

    expect(result, 'done');
    expect(File(seen!).existsSync(), isFalse);
    expect(await LocalMemoryImages.withPlainCopy('missing', (_) async => 'x'), isNull);
  });

  test('a readable copy is removed even when the use fails', () async {
    await LocalMemoryImages.write('m1', png);
    String? seen;
    await expectLater(
      LocalMemoryImages.withPlainCopy('m1', (path) async {
        seen = path;
        throw StateError('gallery refused');
      }),
      throwsStateError,
    );
    expect(File(seen!).existsSync(), isFalse);
  });

  test('without the local key nothing is written, and nothing is read', () async {
    LocalMemoryImages.unconfigure();

    await expectLater(LocalMemoryImages.write('m1', png), throwsStateError);
    expect(file('m1').existsSync(), isFalse, reason: 'never a readable file instead');

    file('old').writeAsBytesSync(png);
    expect(await LocalMemoryImages.read('old'), isNull);
    expect(file('old').readAsBytesSync(), png, reason: 'an older picture is left alone until the key is ready');
  });

  test('delete and deleteAll remove pictures', () async {
    await LocalMemoryImages.write('m1', png);
    await LocalMemoryImages.write('m2', png);
    await LocalMemoryImages.delete('m1');
    expect(await LocalMemoryImages.ids(), {'m2'});
    await LocalMemoryImages.deleteAll();
    expect(dir.existsSync(), isFalse);
    dir.createSync();
  });
}
