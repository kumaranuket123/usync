import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/crypto_service.dart';

Uint8List hex(String s) => Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

String toHex(List<int> b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final crypto = CryptoService();
  final aad = CryptoService.fieldAad(coupleId: 'c1', table: 'bucket_items', rowId: 'r1', field: 'enc');

  group('published test vectors (the primitives behave as specified)', () {
    test('X25519 (RFC 7748 section 6.1) gives both sides the same shared secret', () async {
      final x = X25519();
      final alice = await x.newKeyPairFromSeed(hex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'));
      final bob   = await x.newKeyPairFromSeed(hex('5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb'));
      final alicePub = await alice.extractPublicKey();
      final bobPub   = await bob.extractPublicKey();
      expect(toHex(alicePub.bytes), '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a');
      expect(toHex(bobPub.bytes),   'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f');
      final shared = await x.sharedSecretKey(keyPair: alice, remotePublicKey: bobPub);
      expect(toHex(await shared.extractBytes()), '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742');
    });

    test('HKDF-SHA256 (RFC 5869 test case 1)', () async {
      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 42);
      final okm = await hkdf.deriveKey(
        secretKey: SecretKey(hex('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b')),
        nonce: hex('000102030405060708090a0b0c'),
        info: hex('f0f1f2f3f4f5f6f7f8f9'),
      );
      expect(toHex(await okm.extractBytes()),
          '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865');
    });
  });

  group('envelopes', () {
    test('seal then open returns the original text', () async {
      final key = crypto.newSecretKey();
      final sealed = await crypto.seal('Watch the sunrise 🌅', key: key, aad: aad);
      expect(sealed, startsWith('u1:'));
      expect(crypto.isEnvelope(sealed), isTrue);
      expect(sealed, isNot(contains('sunrise')));
      expect(await crypto.open(sealed, key: key, aad: aad), 'Watch the sunrise 🌅');
    });

    test('the same text seals differently every time (a fresh nonce)', () async {
      final key = crypto.newSecretKey();
      final nonces = <String>{};
      for (var i = 0; i < 50; i++) {
        final bytes = await crypto.sealBytes(utf8.encode('same'), key: key, aad: aad);
        nonces.add(toHex(bytes.sublist(1, 13)));
      }
      expect(nonces, hasLength(50));
    });

    test('empty and large values work', () async {
      final key = crypto.newSecretKey();
      expect(await crypto.open(await crypto.seal('', key: key, aad: aad), key: key, aad: aad), '');
      final big = Uint8List.fromList(List<int>.generate(2 * 1024 * 1024, (i) => i % 251));
      final opened = await crypto.openBytes(await crypto.sealBytes(big, key: key, aad: aad), key: key, aad: aad);
      expect(opened, big);
    });

    test('JSON round-trips', () async {
      final key = crypto.newSecretKey();
      final sealed = await crypto.sealJson({'title': 'Paris', 'emoji': '✈️', 'n': 3}, key: key, aad: aad);
      expect(await crypto.openJson(sealed, key: key, aad: aad), {'title': 'Paris', 'emoji': '✈️', 'n': 3});
    });

    test('a wrong key cannot open it', () async {
      final sealed = await crypto.seal('secret', key: crypto.newSecretKey(), aad: aad);
      await expectLater(crypto.open(sealed, key: crypto.newSecretKey(), aad: aad), throwsA(isA<CryptoException>()));
    });

    test('different associated data cannot open it: a value cannot be moved to another row, field or couple', () async {
      final key = crypto.newSecretKey();
      final sealed = await crypto.seal('secret', key: key, aad: aad);
      for (final other in [
        CryptoService.fieldAad(coupleId: 'c2', table: 'bucket_items', rowId: 'r1', field: 'enc'),
        CryptoService.fieldAad(coupleId: 'c1', table: 'moods', rowId: 'r1', field: 'enc'),
        CryptoService.fieldAad(coupleId: 'c1', table: 'bucket_items', rowId: 'r2', field: 'enc'),
        CryptoService.fieldAad(coupleId: 'c1', table: 'bucket_items', rowId: 'r1', field: 'note'),
      ]) {
        await expectLater(crypto.open(sealed, key: key, aad: other), throwsA(isA<CryptoException>()));
      }
    });

    test('changing any single byte is detected', () async {
      final key = crypto.newSecretKey();
      final bytes = await crypto.sealBytes(utf8.encode('secret value'), key: key, aad: aad);
      for (var i = 0; i < bytes.length; i++) {
        final tampered = Uint8List.fromList(bytes)..[i] ^= 0x01;
        await expectLater(crypto.openBytes(tampered, key: key, aad: aad), throwsA(isA<CryptoException>()), reason: 'byte $i');
      }
    });

    test('a truncated or malformed value is rejected, not crashed on', () async {
      final key = crypto.newSecretKey();
      final sealed = await crypto.seal('secret', key: key, aad: aad);
      for (final bad in ['', 'u1:', 'u1:AAAA', 'plain text', 'u1:%%%', sealed.substring(0, sealed.length - 8), 'w1:${sealed.substring(3)}']) {
        await expectLater(crypto.open(bad, key: key, aad: aad), throwsA(isA<CryptoException>()), reason: bad);
      }
    });

    test('an unknown version is rejected', () async {
      final key = crypto.newSecretKey();
      final bytes = await crypto.sealBytes(utf8.encode('x'), key: key, aad: aad);
      final changed = Uint8List.fromList(bytes)..[0] = 9;
      await expectLater(crypto.openBytes(changed, key: key, aad: aad), throwsA(isA<CryptoException>()));
    });

    test('plain text is not an envelope', () {
      expect(crypto.isEnvelope('Watch the sunrise'), isFalse);
    });
  });

  group('key wrapping (authenticated)', () {
    Future<(SimpleKeyPair, List<int>)> identity() async {
      final pair = await crypto.keyPairFromSeed(crypto.randomBytes(32));
      return (pair, (await pair.extractPublicKey()).bytes);
    }

    test('only the recipient can open it, and only if it came from the expected sender', () async {
      final (alice, alicePub) = await identity();
      final (bob, bobPub) = await identity();
      final (eve, _) = await identity();
      final secret = crypto.randomBytes(32);
      final aad = CryptoService.aadOf('couple-key', ['c1', '1', 'bob']);

      final wrapped = await crypto.wrapKey(secret, sender: alice, recipientPublicKey: bobPub, aad: aad);

      expect(wrapped, startsWith('w2:'));
      expect(await crypto.unwrapKey(wrapped, recipient: bob, senderPublicKey: alicePub, aad: aad), secret);
      await expectLater(crypto.unwrapKey(wrapped, recipient: eve, senderPublicKey: alicePub, aad: aad), throwsA(isA<CryptoException>()));
    });

    test('a server that knows both public keys cannot forge a key that the recipient accepts', () async {
      // The attacker can write database rows and knows Alice's and Bob's PUBLIC keys, but has no private key of theirs.
      final (_, alicePub) = await identity();
      final (bob, bobPub) = await identity();
      final (attacker, _) = await identity();
      final aad = CryptoService.aadOf('couple-key', ['c1', '1', 'bob']);
      final chosenByAttacker = crypto.randomBytes(32);

      final forged = await crypto.wrapKey(chosenByAttacker, sender: attacker, recipientPublicKey: bobPub, aad: aad);

      // Bob expects the key to come from Alice: it does not open, so he never adopts the attacker's key.
      await expectLater(crypto.unwrapKey(forged, recipient: bob, senderPublicKey: alicePub, aad: aad), throwsA(isA<CryptoException>()));
    });

    test('a sender can also wrap a key for themselves', () async {
      final (alice, alicePub) = await identity();
      final secret = crypto.randomBytes(32);
      final aad = CryptoService.aadOf('couple-key', ['c1', '1', 'alice']);
      final wrapped = await crypto.wrapKey(secret, sender: alice, recipientPublicKey: alicePub, aad: aad);
      expect(await crypto.unwrapKey(wrapped, recipient: alice, senderPublicKey: alicePub, aad: aad), secret);
    });

    test('the purpose must match, and each wrap is different', () async {
      final (alice, alicePub) = await identity();
      final (bob, bobPub) = await identity();
      final secret = crypto.randomBytes(32);
      final a = await crypto.wrapKey(secret, sender: alice, recipientPublicKey: bobPub, aad: CryptoService.aadOf('couple-key', ['c1']));
      final b = await crypto.wrapKey(secret, sender: alice, recipientPublicKey: bobPub, aad: CryptoService.aadOf('couple-key', ['c1']));
      expect(a, isNot(b));
      await expectLater(
        crypto.unwrapKey(a, recipient: bob, senderPublicKey: alicePub, aad: CryptoService.aadOf('couple-key', ['c2'])),
        throwsA(isA<CryptoException>()),
      );
    });

    test('a tampered wrapped key is rejected', () async {
      final (alice, alicePub) = await identity();
      final (bob, bobPub) = await identity();
      final aad = CryptoService.aadOf('couple-key');
      final wrapped = await crypto.wrapKey(crypto.randomBytes(32), sender: alice, recipientPublicKey: bobPub, aad: aad);
      final bytes = base64Url.decode(base64Url.normalize(wrapped.substring(3)));
      for (final i in [0, 31, 32, 40, bytes.length - 1]) {
        final t = Uint8List.fromList(bytes)..[i] ^= 0x01;
        await expectLater(
          crypto.unwrapKey('w2:${base64Url.encode(t)}', recipient: bob, senderPublicKey: alicePub, aad: aad),
          throwsA(isA<CryptoException>()),
          reason: 'byte $i',
        );
      }
    });

    test('an all-zero (low-order) public key is refused, as recipient or as sender', () async {
      final (alice, alicePub) = await identity();
      final (bob, bobPub) = await identity();
      await expectLater(
        crypto.wrapKey(crypto.randomBytes(32), sender: alice, recipientPublicKey: Uint8List(32), aad: const []),
        throwsA(isA<CryptoException>()),
      );
      final wrapped = await crypto.wrapKey(crypto.randomBytes(32), sender: alice, recipientPublicKey: bobPub, aad: const []);
      await expectLater(crypto.unwrapKey(wrapped, recipient: bob, senderPublicKey: Uint8List(32), aad: const []), throwsA(isA<CryptoException>()));
      expect(alicePub, hasLength(32));
    });

    test('keys of the wrong size are refused', () async {
      final (alice, _) = await identity();
      await expectLater(crypto.wrapKey(crypto.randomBytes(32), sender: alice, recipientPublicKey: [1, 2, 3], aad: const []), throwsA(isA<CryptoException>()));
      await expectLater(crypto.unwrapKey('w2:AAAA', recipient: alice, senderPublicKey: [1, 2, 3], aad: const []), throwsA(isA<CryptoException>()));
      await expectLater(crypto.keyPairFromSeed([1, 2, 3]), throwsA(isA<CryptoException>()));
    });

    test('the old unauthenticated format is not accepted', () async {
      final (bob, bobPub) = await identity();
      await expectLater(crypto.unwrapKey('w1:AAAA', recipient: bob, senderPublicKey: bobPub, aad: const []), throwsA(isA<CryptoException>()));
    });
  });

  group('associated data', () {
    test('different field tuples never produce the same bytes, whatever characters they contain', () {
      final seen = <String>{};
      final tuples = [
        ('c', 't', 'a|b', 'c'),
        ('c', 't', 'a', 'b|c'),
        ('c', 't|a', 'b', 'c'),
        ('c|t', 'a', 'b', 'c'),
        ('c', 't', 'a', 'bc'),
        ('c', 't', 'ab', 'c'),
        ('', 'c', 't', 'a'),
        ('c', '', 't', 'a'),
      ];
      for (final (c, t, r, f) in tuples) {
        final bytes = CryptoService.fieldAad(coupleId: c, table: t, rowId: r, field: f);
        expect(seen.add(base64.encode(bytes)), isTrue, reason: '($c, $t, $r, $f) collided with another tuple');
      }
    });

    test('a field AAD never equals a free-form AAD', () {
      expect(
        CryptoService.fieldAad(coupleId: 'x', table: 'y', rowId: 'z', field: 'w'),
        isNot(CryptoService.aadOf('x', ['y', 'z', 'w'])),
      );
      expect(CryptoService.aadOf('a', ['b', 'c']), isNot(CryptoService.aadOf('a', ['b|c'])));
      expect(CryptoService.aadOf('a', ['bc']), isNot(CryptoService.aadOf('a', ['b', 'c'])));
    });

    test('is stable', () {
      expect(CryptoService.aadOf('p', ['1', '2']), CryptoService.aadOf('p', ['1', '2']));
    });
  });

  group('security code', () {
    test('is 12 groups of 5 digits', () async {
      final code = await crypto.securityCode(crypto.randomBytes(32), crypto.randomBytes(32));
      expect(code, matches(RegExp(r'^(\d{5} ){11}\d{5}$')));
    });

    test('is the same whichever partner computes it, and stable', () async {
      final a = crypto.randomBytes(32);
      final b = crypto.randomBytes(32);
      expect(await crypto.securityCode(a, b), await crypto.securityCode(b, a));
      expect(await crypto.securityCode(a, b), await crypto.securityCode(a, b));
    });

    test('changes if either key is swapped', () async {
      final a = crypto.randomBytes(32);
      final b = crypto.randomBytes(32);
      final c = crypto.randomBytes(32);
      final original = await crypto.securityCode(a, b);
      expect(await crypto.securityCode(a, c), isNot(original));
      expect(await crypto.securityCode(c, b), isNot(original));
    });
  });

  group('recovery key', () {
    test('is derived from the entropy, deterministically and only from it', () async {
      final entropy = hex('000102030405060708090a0b0c0d0e0f');
      final k1 = await (await crypto.backupKeyFromEntropy(entropy)).extractBytes();
      final k2 = await (await crypto.backupKeyFromEntropy(entropy)).extractBytes();
      final k3 = await (await crypto.backupKeyFromEntropy(hex('000102030405060708090a0b0c0d0e10'))).extractBytes();
      expect(k1, k2);
      expect(k1, isNot(k3));
      expect(k1, hasLength(32));
    });
  });

  test('random keys and bytes differ every time', () {
    expect(crypto.randomBytes(32), isNot(crypto.randomBytes(32)));
    expect(crypto.randomBytes(0), isEmpty);
  });
}
