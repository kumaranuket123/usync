import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/core/crypto/crypto_service.dart';
import 'package:usync/core/crypto/key_service.dart';

import '../../support/in_memory_key_store.dart';
import '../../support/test_cipher.dart';

void main() {
  const place = (coupleId: 'c1', table: 'moods', rowId: 'r1');

  Future<String> seal(ContentCipher c, Map<String, dynamic> v, {String field = 'enc'}) =>
      c.sealJson(v, coupleId: place.coupleId, table: place.table, rowId: place.rowId, field: field);
  Future<Map<String, dynamic>> open(ContentCipher c, String v, {String coupleId = 'c1', String table = 'moods', String rowId = 'r1', String field = 'enc'}) =>
      c.openJson(v, coupleId: coupleId, table: table, rowId: rowId, field: field);

  test('seals and opens a value, and the envelope hides the content', () async {
    final c = await readyCipher();
    final sealed = await seal(c, {'label': 'Missing you'});
    expect(sealed, startsWith(CryptoService.envelopePrefix));
    expect(sealed, isNot(contains('Missing')));
    expect(await open(c, sealed), {'label': 'Missing you'});
  });

  test('the same content sealed twice gives different ciphertext', () async {
    final c = await readyCipher();
    expect(await seal(c, {'a': 1}), isNot(await seal(c, {'a': 1})));
  });

  test('a value is bound to its couple, table, row and field', () async {
    final c = await readyCipher(coupleIds: const ['c1', 'c2']);
    final sealed = await seal(c, {'a': 1});
    await expectLater(open(c, sealed, coupleId: 'c2'), throwsA(isA<CryptoException>()));
    await expectLater(open(c, sealed, table: 'bucket_items'), throwsA(isA<CryptoException>()));
    await expectLater(open(c, sealed, rowId: 'r2'), throwsA(isA<CryptoException>()));
    await expectLater(open(c, sealed, field: 'detail'), throwsA(isA<CryptoException>()));
  });

  test('a changed value does not open', () async {
    final c = await readyCipher();
    final sealed = await seal(c, {'a': 1});
    final flipped = '${sealed.substring(0, sealed.length - 2)}${sealed.endsWith('A') ? 'B' : 'A'}${sealed.substring(sealed.length - 1)}';
    await expectLater(open(c, flipped), throwsA(isA<CryptoException>()));
  });

  test('two partners sharing the couple key read each other; a different key does not', () async {
    final keys = KeyService(store: InMemoryKeyStore(), namespace: 'x');
    final shared = await keys.newCoupleKeyBytes();
    final a = await readyCipher(userId: 'a', coupleKey: shared);
    final b = await readyCipher(userId: 'b', coupleKey: shared);
    final stranger = await readyCipher(userId: 's');

    final sealed = await seal(a, {'hello': 'b'});

    expect(await open(b, sealed), {'hello': 'b'});
    await expectLater(open(stranger, sealed), throwsA(isA<CryptoException>()));
  });

  test('text values round-trip too', () async {
    final c = await readyCipher();
    final sealed = await c.sealText('hi 💜', coupleId: 'c1', table: 'question_answers', rowId: 'u:1', field: 'answer');
    expect(await c.openText(sealed, coupleId: 'c1', table: 'question_answers', rowId: 'u:1', field: 'answer'), 'hi 💜');
  });

  group('without the couple key', () {
    test('isReady is false and sealing or opening throws EncryptionNotReady', () async {
      final ready = await readyCipher();
      final sealed = await seal(ready, {'a': 1});
      final c = notReadyCipher();

      expect(await c.isReady('c1'), isFalse);
      await expectLater(seal(c, {'a': 1}), throwsA(isA<EncryptionNotReady>()));
      await expectLater(open(c, sealed), throwsA(isA<EncryptionNotReady>()));
    });

    test('a key for another couple does not make this one ready', () async {
      final c = await readyCipher(coupleIds: const ['other']);
      expect(await c.isReady('c1'), isFalse);
      expect(await c.isReady('other'), isTrue);
    });

    test('nobody signed in is not ready', () async {
      final store = InMemoryKeyStore();
      final c = ContentCipher(keysFor: (uid) => KeyService(store: store, namespace: uid), currentUserId: () => null);
      expect(await c.isReady('c1'), isFalse);
      await expectLater(seal(c, {'a': 1}), throwsA(isA<EncryptionNotReady>()));
    });

    test('the message points the person to Profile → Security', () {
      expect(const EncryptionNotReady().message, contains('Profile'));
    });
  });

  test('isEncrypted recognises only an envelope', () {
    expect(ContentCipher.isEncrypted('u1:abc'), isTrue);
    expect(ContentCipher.isEncrypted('plain text'), isFalse);
    expect(ContentCipher.isEncrypted(null), isFalse);
  });
}
