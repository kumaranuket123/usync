import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/crypto_service.dart';
import 'package:usync/core/crypto/key_service.dart';

import '../../support/in_memory_key_store.dart';

void main() {
  late InMemoryKeyStore store;
  late KeyService keys;

  setUp(() {
    store = InMemoryKeyStore();
    keys = KeyService(store: store);
  });

  group('identity key', () {
    test('is made only by createIdentity, and reading it with none present is an error, not a new key', () async {
      expect(await keys.hasIdentity(), isFalse);
      await expectLater(keys.publicKeyBytes(), throwsA(isA<CryptoException>()));
      await expectLater(keys.identityKeyPair(), throwsA(isA<CryptoException>()));
      expect(await keys.hasIdentity(), isFalse, reason: 'reading must never create a key');
    });

    test('is created once and is the same afterwards, even from a new service', () async {
      expect(await keys.hasIdentity(), isFalse);
      await keys.createIdentity();
      final first = await keys.publicKeyBytes();
      expect(first, hasLength(32));
      expect(await keys.hasIdentity(), isTrue);
      expect(await keys.publicKeyBytes(), first);
      expect(await KeyService(store: store).publicKeyBytes(), first, reason: 'it was saved, not just kept in memory');
    });

    test('different phones get different keys', () async {
      await keys.createIdentity();
      final other = KeyService(store: InMemoryKeyStore());
      await other.createIdentity();
      expect(await keys.publicKeyBytes(), isNot(await other.publicKeyBytes()));
    });

    test('resetting makes a new key', () async {
      await keys.createIdentity();
      final before = await keys.publicKeyBytes();
      await keys.resetIdentity();
      expect(await keys.publicKeyBytes(), isNot(before));
    });

    test('createIdentity does not replace an existing identity', () async {
      await keys.createIdentity();
      final before = await keys.publicKeyBytes();
      await keys.createIdentity();
      expect(await keys.publicKeyBytes(), before);
    });

    test('only the 32-byte seed is stored (as text), not the public key', () async {
      await keys.createIdentity();
      expect(store.values, hasLength(1));
      expect(base64Decode(store.values.values.single), hasLength(32));
    });
  });

  group('couple keys', () {
    test('are stored per couple and version', () async {
      final k = await keys.newCoupleKeyBytes();
      expect(k, hasLength(32));
      expect(await keys.hasCoupleKey('c1'), isFalse);
      await keys.storeCoupleKey('c1', k);
      expect(await keys.hasCoupleKey('c1'), isTrue);
      expect(await (await keys.coupleKey('c1'))!.extractBytes(), k);
      expect(await keys.coupleKey('c2'), isNull);
      expect(await keys.coupleKey('c1', version: 2), isNull);
    });

    test('a key of the wrong size is refused', () async {
      await expectLater(keys.storeCoupleKey('c1', [1, 2, 3]), throwsA(isA<CryptoException>()));
    });

    test('forgetting a couple removes only that couple', () async {
      await keys.storeCoupleKey('c1', await keys.newCoupleKeyBytes());
      await keys.storeCoupleKey('c1', await keys.newCoupleKeyBytes(), version: 2);
      await keys.storeCoupleKey('c2', await keys.newCoupleKeyBytes());
      await keys.forgetCouple('c1');
      expect(await keys.hasCoupleKey('c1'), isFalse);
      expect(await keys.hasCoupleKey('c1', version: 2), isFalse);
      expect(await keys.hasCoupleKey('c2'), isTrue);
    });

    test('a couple key really encrypts and decrypts', () async {
      await keys.storeCoupleKey('c1', await keys.newCoupleKeyBytes());
      final key = (await keys.coupleKey('c1'))!;
      final aad = CryptoService.fieldAad(coupleId: 'c1', table: 'moods', rowId: 'r', field: 'enc');
      final sealed = await keys.crypto.seal('hello', key: key, aad: aad);
      expect(await keys.crypto.open(sealed, key: key, aad: aad), 'hello');
    });
  });

  group('recovery phrase', () {
    test('a new phrase has 12 valid words and they differ each time', () {
      final p = KeyService.newRecoveryPhrase();
      expect(p.split(' '), hasLength(12));
      expect(KeyService.isValidPhrase(p), isTrue);
      expect(KeyService.newRecoveryPhrase(), isNot(p));
    });

    test('the official BIP39 test vector is valid, a bad checksum or length is not', () {
      expect(KeyService.isValidPhrase('abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'), isTrue);
      expect(KeyService.isValidPhrase('abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon'), isFalse);
      expect(KeyService.isValidPhrase('abandon abandon abandon'), isFalse);
      expect(KeyService.isValidPhrase('notaword ' * 12), isFalse);
      expect(KeyService.isValidPhrase(''), isFalse);
    });

    test('capitals and extra spaces are forgiven', () {
      expect(KeyService.normalizePhrase('  Abandon   ABANDON\nabandon '), 'abandon abandon abandon');
      expect(KeyService.isValidPhrase('  ABANDON abandon  abandon abandon abandon abandon abandon abandon abandon abandon abandon ABOUT  '), isTrue);
    });

    test('a backup restores the identity key on a fresh phone with the right phrase', () async {
      final phrase = KeyService.newRecoveryPhrase();
      await keys.createIdentity();
      final original = await keys.publicKeyBytes();
      final backup = await keys.backupIdentity(phrase);
      expect(backup, startsWith('u1:'));

      final newPhone = KeyService(store: InMemoryKeyStore());
      await newPhone.restoreIdentity(phrase: phrase, backup: backup);
      expect(await newPhone.publicKeyBytes(), original);
    });

    test('a wrong phrase, an invalid phrase or a damaged backup does not restore', () async {
      final phrase = KeyService.newRecoveryPhrase();
      await keys.createIdentity();
      final backup = await keys.backupIdentity(phrase);

      final newPhone = KeyService(store: InMemoryKeyStore());
      await expectLater(newPhone.restoreIdentity(phrase: KeyService.newRecoveryPhrase(), backup: backup), throwsA(isA<CryptoException>()));
      await expectLater(newPhone.restoreIdentity(phrase: 'abandon abandon', backup: backup), throwsA(isA<CryptoException>()));
      await expectLater(newPhone.restoreIdentity(phrase: phrase, backup: '${backup.substring(0, backup.length - 4)}AAAA'), throwsA(isA<CryptoException>()));
      expect(await newPhone.hasIdentity(), isFalse, reason: 'a failed restore must not leave a key behind');
    });

    test('opening a backup does not store anything, so it can be checked before it is used', () async {
      final phrase = KeyService.newRecoveryPhrase();
      await keys.createIdentity();
      final seed = base64Decode(store.values.values.single);
      final backup = await keys.backupIdentity(phrase);

      final newPhone = KeyService(store: InMemoryKeyStore());
      final opened = await newPhone.openIdentityBackup(phrase: phrase, backup: backup);

      expect(opened, seed);
      expect(await newPhone.hasIdentity(), isFalse, reason: 'nothing is written until installIdentity');
      await newPhone.installIdentity(opened);
      expect(await newPhone.publicKeyBytes(), await keys.publicKeyBytes());
    });

    test('a failed restore never touches the keys already on the phone', () async {
      final phrase = KeyService.newRecoveryPhrase();
      await keys.createIdentity();
      final backup = await keys.backupIdentity(phrase);
      final other = KeyService(store: InMemoryKeyStore());
      await other.createIdentity();
      final before = await other.publicKeyBytes();

      await expectLater(other.restoreIdentity(phrase: KeyService.newRecoveryPhrase(), backup: backup), throwsA(isA<CryptoException>()));

      expect(await other.publicKeyBytes(), before);
    });

    test('a backup is bound to its account: another account cannot open it', () async {
      final phrase = KeyService.newRecoveryPhrase();
      final a = KeyService(store: store, namespace: 'user-a');
      await a.createIdentity();
      final backup = await a.backupIdentity(phrase);
      final b = KeyService(store: InMemoryKeyStore(), namespace: 'user-b');
      await expectLater(b.openIdentityBackup(phrase: phrase, backup: backup), throwsA(isA<CryptoException>()));
    });

    test('the backup does not contain the key', () async {
      final seed = store.values.isEmpty ? null : store.values.values.single;
      await keys.createIdentity();
      final stored = store.values.values.single;
      final backup = await keys.backupIdentity(KeyService.newRecoveryPhrase());
      expect(seed, isNull);
      expect(backup, isNot(contains(stored)));
    });

    test('there is nothing to back up before an identity exists', () async {
      await expectLater(keys.backupIdentity(KeyService.newRecoveryPhrase()), throwsA(isA<CryptoException>()));
    });
  });

  group('accounts and flags', () {
    test('two accounts on one phone have separate keys', () async {
      final a = KeyService(store: store, namespace: 'user-a');
      final b = KeyService(store: store, namespace: 'user-b');
      await a.createIdentity();
      final pubA = await a.publicKeyBytes();
      expect(await b.hasIdentity(), isFalse);
      await b.createIdentity();
      expect(await b.publicKeyBytes(), isNot(pubA));
      expect(await KeyService(store: store, namespace: 'user-a').publicKeyBytes(), pubA);

      await a.storeCoupleKey('c1', await a.newCoupleKeyBytes());
      expect(await b.hasCoupleKey('c1'), isFalse);
    });

    test('wiping one account leaves the other and the default namespace alone', () async {
      final a = KeyService(store: store, namespace: 'user-a');
      final b = KeyService(store: store, namespace: 'user-b');
      await a.createIdentity();
      await b.createIdentity();
      await a.clearAll();
      expect(await a.hasIdentity(), isFalse);
      expect(await b.hasIdentity(), isTrue);
    });

    test('flags are stored, read, deleted, and wiped with the keys', () async {
      expect(await keys.meta('recovery'), isNull);
      await keys.setMeta('recovery', '1');
      expect(await keys.meta('recovery'), '1');
      await keys.deleteMeta('recovery');
      expect(await keys.meta('recovery'), isNull);

      await keys.setMeta('x', 'y');
      await keys.clearAll();
      expect(await keys.meta('x'), isNull);
    });

    test('forgetting a couple also forgets what we remembered about the partner', () async {
      await keys.storeCoupleKey('c1', await keys.newCoupleKeyBytes());
      await keys.setMeta('partner.c1.key', 'abc');
      await keys.setMeta('partner.c2.key', 'def');
      await keys.forgetCouple('c1');
      expect(await keys.meta('partner.c1.key'), isNull);
      expect(await keys.meta('partner.c2.key'), 'def');
    });
  });

  group('wiping', () {
    test('clearAll removes every key of ours but nothing else', () async {
      store.values['unrelated'] = 'keep me';
      await keys.createIdentity();
      await keys.storeCoupleKey('c1', await keys.newCoupleKeyBytes());

      await keys.clearAll();

      expect(await keys.hasIdentity(), isFalse);
      expect(await keys.hasCoupleKey('c1'), isFalse);
      expect(store.values, {'unrelated': 'keep me'});
    });
  });

  test('two partners can exchange a couple key end to end, authenticated by the sender', () async {
    final alice = KeyService(store: InMemoryKeyStore());
    final bob   = KeyService(store: InMemoryKeyStore());
    await alice.createIdentity();
    await bob.createIdentity();
    final couple = await alice.newCoupleKeyBytes();
    final aad = CryptoService.aadOf('couple-key', ['c1', '1', 'bob']);

    final wrappedForBob = await alice.crypto.wrapKey(
      couple,
      sender: await alice.identityKeyPair(),
      recipientPublicKey: await bob.publicKeyBytes(),
      aad: aad,
    );
    final received = await bob.crypto.unwrapKey(
      wrappedForBob,
      recipient: await bob.identityKeyPair(),
      senderPublicKey: await alice.publicKeyBytes(),
      aad: aad,
    );

    expect(received, couple);
    expect(
      await alice.crypto.securityCode(await alice.publicKeyBytes(), await bob.publicKeyBytes()),
      await bob.crypto.securityCode(await bob.publicKeyBytes(), await alice.publicKeyBytes()),
    );
  });
}
