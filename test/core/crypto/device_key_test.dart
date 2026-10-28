import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/crypto_service.dart';
import 'package:usync/core/crypto/device_key.dart';

import '../../support/in_memory_key_store.dart';

void main() {
  test('creates a 32-byte key once and keeps it in the key store', () async {
    final store = InMemoryKeyStore();
    final key = await DeviceKey(store: store).bytes();

    expect(key, hasLength(32));
    expect(store.values, hasLength(1));
    expect(await DeviceKey(store: store).bytes(), key, reason: 'a later start finds the same key');
  });

  test('callers at the same moment share one creation', () async {
    final store = InMemoryKeyStore();
    final k = DeviceKey(store: store);
    final keys = await Future.wait([k.bytes(), k.bytes(), k.bytes()]);
    expect(keys[0], keys[1]);
    expect(keys[1], keys[2]);
  });

  test('an unreadable stored value is replaced instead of failing', () async {
    final store = InMemoryKeyStore({'usync.local.v1': '!!not base64!!'});
    expect(await DeviceKey(store: store).bytes(), hasLength(32));

    final wrongLength = InMemoryKeyStore({'usync.local.v1': base64Encode([1, 2, 3])});
    expect(await DeviceKey(store: wrongLength).bytes(), hasLength(32));
  });

  group('files', () {
    test('seal hides the content and opens back to it', () async {
      final k = DeviceKey(store: InMemoryKeyStore());
      final plain = utf8.encode('a very private picture');

      final sealed = await k.sealFile('m1', plain);

      expect(utf8.decode(sealed, allowMalformed: true), isNot(contains('private')));
      expect(await k.openFile('m1', sealed), plain);
    });

    test('a file is bound to its name, and a changed or foreign file does not open', () async {
      final k = DeviceKey(store: InMemoryKeyStore());
      final sealed = await k.sealFile('m1', [1, 2, 3, 4]);

      await expectLater(k.openFile('m2', sealed), throwsA(isA<CryptoException>()));
      final flipped = [...sealed]..[sealed.length - 1] ^= 1;
      await expectLater(k.openFile('m1', flipped), throwsA(isA<CryptoException>()));
      await expectLater(DeviceKey(store: InMemoryKeyStore()).openFile('m1', sealed), throwsA(isA<CryptoException>()), reason: 'another phone cannot open it');
    });
  });
}
