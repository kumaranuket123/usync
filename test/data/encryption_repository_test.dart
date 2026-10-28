import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/crypto_service.dart';
import 'package:usync/core/crypto/key_service.dart';
import 'package:usync/domain/entities/encryption_state.dart';

import '../support/fake_encryption_server.dart';
import '../support/in_memory_key_store.dart';

void main() {
  late FakeEncryptionServer server;
  late FakePhone alice; // the inviter
  late FakePhone bob;

  setUp(() {
    server = FakeEncryptionServer();
    alice = FakePhone(server, 'alice', coupleId: 'c1', partnerId: 'bob');
    bob = FakePhone(server, 'bob', coupleId: 'c1', partnerId: 'alice');
  });

  Future<List<int>> coupleKeyOf(FakePhone p) async => (await (await p.keys.coupleKey('c1'))!.extractBytes());

  /// Both phones have opened the app and published their keys; nobody has compared the code yet.
  Future<void> exchangeKeys() async {
    await alice.repo.sync();
    await bob.repo.sync();
    await alice.repo.sync();
  }

  /// Each partner reads the code on their own screen and confirms it, as people comparing out loud would.
  Future<void> verifyBoth() async {
    await alice.repo.markPartnerVerified(alice.repo.current.securityCode!);
    await bob.repo.markPartnerVerified(bob.repo.current.securityCode!);
    await alice.repo.sync();
  }

  Future<void> pairBoth() async {
    await exchangeKeys();
    await verifyBoth();
  }

  /// What a server operator who can write rows, but holds no private key, can do.
  Future<List<int>> attackerPublicKey() async {
    final attacker = KeyService(store: InMemoryKeyStore());
    await attacker.createIdentity();
    return attacker.publicKeyBytes();
  }

  group('first time', () {
    test('an unpaired account makes its key, publishes it, and has nothing more to do', () async {
      alice.coupleId = null;
      alice.partnerId = null;

      final s = await alice.repo.sync();

      expect(s.phase, EncryptionPhase.noCouple);
      expect(s.recoverySetUp, isFalse);
      expect(server.publicKeys['alice'], base64Encode(await alice.keys.publicKeyBytes()));
    });

    test('syncing again does not publish again', () async {
      await alice.repo.sync();
      await alice.repo.sync();
      await alice.repo.sync();
      expect(server.publishCalls, 1);
    });

    test('nothing the server holds can read anything: no private key, no couple key', () async {
      await pairBoth();
      final everything = jsonEncode([server.publicKeys, server.backups, server.coupleKeys]);
      final seed = alice.store.values.entries.firstWhere((e) => e.key.contains('identity.seed')).value;
      final coupleKey = base64Encode(await coupleKeyOf(alice));
      expect(everything, isNot(contains(seed)));
      expect(everything, isNot(contains(coupleKey)));
    });
  });

  group('pairing handshake', () {
    test('the partner has not opened the app yet: wait', () async {
      final s = await alice.repo.sync();
      expect(s.phase, EncryptionPhase.waitingForPartner);
      expect(s.securityCode, isNull);
    });

    test('with both keys known the code must be compared first, and nothing is shared before that', () async {
      await exchangeKeys();

      expect(alice.repo.current.phase, EncryptionPhase.needsVerification);
      expect(bob.repo.current.phase, EncryptionPhase.needsVerification);
      expect(server.coupleKeys, isEmpty, reason: 'no couple key may exist before a person confirmed the code');
      expect(await alice.keys.hasCoupleKey('c1'), isFalse);
      expect(await bob.keys.hasCoupleKey('c1'), isFalse);
    });

    test('both see the same security code', () async {
      await exchangeKeys();
      expect(alice.repo.current.securityCode, bob.repo.current.securityCode);
      expect(alice.repo.current.securityCode, matches(RegExp(r'^(\d{5} ){11}\d{5}$')));
    });

    test('after both confirm, both end up with the same couple key and are ready', () async {
      await pairBoth();
      expect(alice.repo.current.phase, EncryptionPhase.ready);
      expect(bob.repo.current.phase, EncryptionPhase.ready);
      expect(alice.repo.current.partnerVerified, isTrue);
      expect(await coupleKeyOf(alice), await coupleKeyOf(bob));
    });

    test('the first to confirm creates the key; the second waits for it, then takes it', () async {
      await exchangeKeys();
      final a = await alice.repo.markPartnerVerified(alice.repo.current.securityCode!);
      expect(a.phase, EncryptionPhase.ready);
      final b = await bob.repo.markPartnerVerified(bob.repo.current.securityCode!);
      expect(b.phase, EncryptionPhase.ready);
      expect(await coupleKeyOf(alice), await coupleKeyOf(bob));
    });

    test('a second couple key is never created: the first writer wins', () async {
      await pairBoth();
      final before = server.coupleKeys['c1|1']!.values.toList();
      await alice.repo.sync();
      await bob.repo.sync();
      expect(server.coupleKeys['c1|1']!.values.toList(), before);
    });

    test('two phones confirming at the same moment settle on one key', () async {
      await exchangeKeys();
      final results = await Future.wait([
        alice.repo.markPartnerVerified(alice.repo.current.securityCode!),
        bob.repo.markPartnerVerified(bob.repo.current.securityCode!),
      ]);
      expect(results.map((r) => r.phase), everyElement(EncryptionPhase.ready));
      expect(await coupleKeyOf(alice), await coupleKeyOf(bob));
    });

    test('the keys really encrypt between the two phones', () async {
      await pairBoth();
      final crypto = CryptoService();
      final aad = CryptoService.fieldAad(coupleId: 'c1', table: 'moods', rowId: 'm1', field: 'enc');
      final sealed = await crypto.seal('missing you', key: (await alice.keys.coupleKey('c1'))!, aad: aad);
      expect(await crypto.open(sealed, key: (await bob.keys.coupleKey('c1'))!, aad: aad), 'missing you');
    });

    test('a partner key that is not 32 bytes is treated as "not ready", not as a crash', () async {
      await alice.repo.sync();
      server.publicKeys['bob'] = 'not-a-key';
      expect((await alice.repo.sync()).phase, EncryptionPhase.waitingForPartner);
      server.publicKeys['bob'] = base64Encode([1, 2, 3]);
      expect((await alice.repo.sync()).phase, EncryptionPhase.waitingForPartner);
    });
  });

  group('a malicious server (it can write rows but holds no private key)', () {
    test('it cannot choose the couple key: a key sealed by anyone else is never adopted', () async {
      await exchangeKeys();
      // Before anyone confirms, the server writes a couple key of its own choosing, sealed to both partners.
      final attacker = KeyService(store: InMemoryKeyStore());
      await attacker.createIdentity();
      final crypto = CryptoService();
      final chosen = crypto.randomBytes(32);
      Future<String> forged(FakePhone to) async => crypto.wrapKey(
            chosen,
            sender: await attacker.identityKeyPair(),
            recipientPublicKey: await to.keys.publicKeyBytes(),
            aad: CryptoService.aadOf('couple-key', ['c1', '1', to.userId]),
          );
      server.coupleKeys['c1|1'] = {'alice': await forged(alice), 'bob': await forged(bob)};

      final a = await alice.repo.markPartnerVerified(alice.repo.current.securityCode!);
      final b = await bob.repo.markPartnerVerified(bob.repo.current.securityCode!);

      expect(await alice.keys.hasCoupleKey('c1'), isFalse, reason: 'the attacker\'s key must not be stored');
      expect(await bob.keys.hasCoupleKey('c1'), isFalse);
      expect(a.phase, EncryptionPhase.needsApproval);
      expect(b.phase, EncryptionPhase.needsApproval);
    });

    test('overwriting just one partner\'s copy does not make that partner adopt the attacker\'s key', () async {
      await pairBoth();
      final realKey = await coupleKeyOf(bob);
      // Bob's phone is replaced (restored from the phrase), and the server tampered with Bob's row meanwhile.
      final phrase = bob.repo.newRecoveryPhrase();
      await bob.repo.finishRecovery(phrase);
      final attacker = KeyService(store: InMemoryKeyStore());
      await attacker.createIdentity();
      server.coupleKeys['c1|1']!['bob'] = await CryptoService().wrapKey(
        CryptoService().randomBytes(32),
        sender: await attacker.identityKeyPair(),
        recipientPublicKey: await bob.keys.publicKeyBytes(),
        aad: CryptoService.aadOf('couple-key', ['c1', '1', 'bob']),
      );

      final phone2 = bob.newPhone();
      await phone2.repo.sync();
      await phone2.repo.restoreWithPhrase(phrase);
      final s = await phone2.repo.markPartnerVerified(phone2.repo.current.securityCode!);

      expect(s.phase, EncryptionPhase.needsApproval);
      expect(await phone2.keys.hasCoupleKey('c1'), isFalse);
      expect(await coupleKeyOf(alice), realKey, reason: 'Alice still holds the real key');
    });

    test('a swapped partner key gives a different code on each side, and gets no couple key before anyone confirms', () async {
      await alice.repo.sync(); // Alice's key is out
      server.publicKeys['bob'] = base64Encode(await attackerPublicKey()); // the server substitutes Bob's key for Alice
      await alice.repo.sync();
      server.publicKeys.remove('bob'); // (Bob's own phone publishes his real key later)
      await bob.repo.sync();

      expect(server.coupleKeys, isEmpty, reason: 'no key is shared until the code has been confirmed');
      // Alice computed her code against the attacker's key; Bob computes his against Alice's real key.
      final seenByAlice = alice.repo.current.securityCode;
      server.publicKeys['bob'] = base64Encode(await bob.keys.publicKeyBytes());
      await alice.repo.sync();
      expect(seenByAlice, isNotNull);
      expect(seenByAlice, isNot(bob.repo.current.securityCode), reason: 'comparing out loud would reveal the swap');
    });

    test('"They match" confirms only the code the person saw, not what the server serves afterwards', () async {
      await exchangeKeys();
      final shown = alice.repo.current.securityCode!;
      server.publicKeys['bob'] = base64Encode(await attackerPublicKey()); // swapped after the screen was drawn

      await expectLater(alice.repo.markPartnerVerified(shown), throwsA(isA<CryptoException>()));

      expect(await alice.keys.meta('partner.c1.verified'), isNull);
      expect(server.coupleKeys, isEmpty);
      expect(alice.repo.current.phase, isNot(EncryptionPhase.ready));
    });

    test('approving a changed key confirms only the code the person saw', () async {
      await pairBoth();
      await bob.repo.resetKeys();
      await alice.repo.sync();
      final shown = alice.repo.current.securityCode!;
      final before = server.coupleKeys['c1|1']!['bob'];
      server.publicKeys['bob'] = base64Encode(await attackerPublicKey());

      await expectLater(alice.repo.approvePartnerKey(shown), throwsA(isA<CryptoException>()));

      expect(server.coupleKeys['c1|1']!['bob'], before, reason: 'the couple key must not be re-sealed to a key the person did not compare');
    });
  });

  group('verification and a changed partner key', () {
    test('confirming a stale or wrong code is refused', () async {
      await exchangeKeys();
      await expectLater(alice.repo.markPartnerVerified('00000 00000 00000 00000 00000 00000 00000 00000 00000 00000 00000 00000'), throwsA(isA<CryptoException>()));
      expect(alice.repo.current.phase, EncryptionPhase.needsVerification);
    });

    test('when the partner makes new keys, the other side is warned and nothing is trusted automatically', () async {
      await pairBoth();
      final keyBefore = await coupleKeyOf(alice);

      await bob.repo.resetKeys();
      final a = await alice.repo.sync();

      expect(a.phase, EncryptionPhase.partnerKeyChanged);
      expect(a.partnerVerified, isFalse);
      expect(await coupleKeyOf(alice), keyBefore, reason: 'the couple key itself does not change');
    });

    test('confirming the code is not the same as approving the new key', () async {
      await pairBoth();
      await bob.repo.resetKeys();
      await alice.repo.sync();

      final s = await alice.repo.markPartnerVerified(alice.repo.current.securityCode!);

      expect(s.phase, EncryptionPhase.partnerKeyChanged, reason: 'only an explicit approval re-shares the key');
      expect(server.coupleKeys['c1|1']!['bob'], isNot(await _wrappedForBobNow(alice, bob)));
    });

    test('the partner who reset waits until it is approved, then reads again', () async {
      await pairBoth();
      final key = await coupleKeyOf(bob);

      await bob.keys.clearAll(); // bob lost his phone, and the phrase
      final fresh = bob.newPhone();
      expect((await fresh.repo.sync()).phase, EncryptionPhase.needsRestore);
      await fresh.repo.resetKeys();
      expect((await fresh.repo.sync()).phase, EncryptionPhase.needsVerification);

      // Both compare the new code.
      await alice.repo.sync();
      expect(alice.repo.current.phase, EncryptionPhase.partnerKeyChanged);
      expect(alice.repo.current.securityCode, fresh.repo.current.securityCode);
      final waiting = await fresh.repo.markPartnerVerified(fresh.repo.current.securityCode!);
      expect(waiting.phase, EncryptionPhase.needsApproval, reason: 'the old sealed copy is for his old key');

      expect((await alice.repo.approvePartnerKey(alice.repo.current.securityCode!)).phase, EncryptionPhase.ready);
      final b = await fresh.repo.sync();

      expect(b.phase, EncryptionPhase.ready);
      expect(await (await fresh.keys.coupleKey('c1'))!.extractBytes(), key);
    });

    test('approving changes the security code, and it must be confirmed again', () async {
      await pairBoth();
      final codeBefore = alice.repo.current.securityCode;
      await bob.repo.resetKeys();
      await alice.repo.sync();
      final a = await alice.repo.approvePartnerKey(alice.repo.current.securityCode!);
      expect(a.securityCode, isNot(codeBefore));
      expect(a.partnerVerified, isTrue, reason: 'approving means this exact code was compared');
    });

    test('after my OWN keys change, my earlier confirmation no longer counts', () async {
      await pairBoth();
      expect(alice.repo.current.partnerVerified, isTrue);

      final s = await alice.repo.resetKeys();

      expect(s.partnerVerified, isFalse);
      expect(s.phase, EncryptionPhase.needsVerification);
    });
  });

  group('recovery phrase and a new phone', () {
    test('saving a recovery phrase stores only a sealed backup on the server', () async {
      await alice.repo.sync();
      final phrase = alice.repo.newRecoveryPhrase();
      final s = await alice.repo.finishRecovery(phrase);

      expect(s.recoverySetUp, isTrue);
      expect(server.backups['alice'], startsWith('u1:'));
      expect(jsonEncode(server.backups), isNot(contains(phrase.split(' ').first)));
    });

    test('a new phone asks to restore instead of making keys of its own', () async {
      await pairBoth();
      await alice.repo.finishRecovery(alice.repo.newRecoveryPhrase());
      final published = server.publicKeys['alice'];

      final s = await alice.newPhone().repo.sync();

      expect(s.phase, EncryptionPhase.needsRestore);
      expect(server.publicKeys['alice'], published, reason: 'the partner must not be locked out');
    });

    test('the right phrase restores the same keys, and after confirming the code the couple key too', () async {
      await pairBoth();
      final phrase = alice.repo.newRecoveryPhrase();
      await alice.repo.finishRecovery(phrase);
      final key = await coupleKeyOf(alice);
      final codeBefore = alice.repo.current.securityCode;

      final phone2 = alice.newPhone();
      expect((await phone2.repo.sync()).phase, EncryptionPhase.needsRestore);
      final restored = await phone2.repo.restoreWithPhrase(phrase);

      expect(restored.phase, EncryptionPhase.needsVerification, reason: 'a new phone confirms the code again');
      expect(restored.recoverySetUp, isTrue);
      expect(restored.securityCode, codeBefore, reason: 'same keys, so the same code');
      expect(base64Encode(await phone2.keys.publicKeyBytes()), server.publicKeys['alice']);

      final s = await phone2.repo.markPartnerVerified(restored.securityCode!);
      expect(s.phase, EncryptionPhase.ready);
      expect(await (await phone2.keys.coupleKey('c1'))!.extractBytes(), key);
    });

    test('a wrong phrase restores nothing and leaves no key behind', () async {
      await pairBoth();
      await alice.repo.finishRecovery(alice.repo.newRecoveryPhrase());
      final phone2 = alice.newPhone();
      await phone2.repo.sync();

      await expectLater(phone2.repo.restoreWithPhrase(KeyService.newRecoveryPhrase()), throwsA(isA<CryptoException>()));
      expect(await phone2.keys.hasIdentity(), isFalse);
    });

    test('restoring with no backup on the server is refused', () async {
      await pairBoth();
      final phone2 = alice.newPhone();
      await phone2.repo.sync();
      await expectLater(phone2.repo.restoreWithPhrase(KeyService.newRecoveryPhrase()), throwsA(isA<CryptoException>()));
    });

    test('an OLD backup and phrase (kept by the server after a reset) can never wipe the keys on this phone', () async {
      await pairBoth();
      final oldPhrase = alice.repo.newRecoveryPhrase();
      await alice.repo.finishRecovery(oldPhrase);
      final oldBackup = server.backups['alice']!;

      // Alice resets her keys; the server (or a stale copy) still serves the old backup.
      await alice.repo.resetKeys();
      server.backups['alice'] = oldBackup;
      final newPublic = await alice.keys.publicKeyBytes();
      final coupleKey = await coupleKeyOf(alice);

      await expectLater(alice.repo.restoreWithPhrase(oldPhrase), throwsA(isA<CryptoException>()));

      expect(await alice.keys.hasIdentity(), isTrue, reason: 'nothing was wiped');
      expect(await alice.keys.publicKeyBytes(), newPublic, reason: 'the current identity was not replaced');
      expect(await coupleKeyOf(alice), coupleKey, reason: 'the couple key was not wiped either');
    });

    test('resetting keys removes the old backup and the recovery flag', () async {
      await pairBoth();
      await alice.repo.finishRecovery(alice.repo.newRecoveryPhrase());
      final s = await alice.repo.resetKeys();
      expect(server.backups, isEmpty);
      expect(s.recoverySetUp, isFalse);
      expect(server.publicKeys['alice'], base64Encode(await alice.keys.publicKeyBytes()));
    });
  });

  group('two phones of one account', () {
    test('a phone whose key differs from the published one does not overwrite it', () async {
      await pairBoth();
      final published = server.publicKeys['alice'];
      await alice.keys.resetIdentity(); // this phone diverged without publishing
      final s = await alice.repo.sync();
      expect(s.phase, EncryptionPhase.needsRestore);
      expect(server.publicKeys['alice'], published);
    });
  });

  group('operations never interleave', () {
    test('a sync running while keys are reset cannot publish the old key over the new one', () async {
      await pairBoth();
      final inFlight = alice.repo.sync(); // not awaited: it is already running
      final reset = alice.repo.resetKeys();
      await Future.wait([inFlight, reset]);

      expect(server.publicKeys['alice'], base64Encode(await alice.keys.publicKeyBytes()));
      expect(alice.repo.current.phase, isNot(EncryptionPhase.needsRestore));
    });

    test('syncing twice at once shares one run', () async {
      final results = await Future.wait([alice.repo.sync(), alice.repo.sync()]);
      expect(results.first, results.last);
      expect(server.publishCalls, 1);
    });
  });

  group('starting fresh', () {
    /// Both phones are reinstalled and nobody has the recovery phrase: the server holds a key nobody can open.
    Future<(FakePhone, FakePhone)> bothLost() async {
      await pairBoth();
      await alice.keys.clearAll();
      await bob.keys.clearAll();
      final a = alice.newPhone();
      final b = bob.newPhone();
      await a.repo.resetKeys();
      await b.repo.resetKeys();
      await a.repo.sync();
      await b.repo.sync();
      await a.repo.markPartnerVerified(a.repo.current.securityCode!);
      await b.repo.markPartnerVerified(b.repo.current.securityCode!);
      return (a, b);
    }

    test('a stuck couple clears the old key and both phones end up with the same new one', () async {
      final (a, b) = await bothLost();
      expect(a.repo.current.phase, EncryptionPhase.needsApproval);
      expect(b.repo.current.phase, EncryptionPhase.needsApproval);

      expect((await a.repo.startFresh()).phase, EncryptionPhase.ready);
      expect(server.startFreshCalls, 1);
      expect((await b.repo.sync()).phase, EncryptionPhase.ready);
      expect(await (await a.keys.coupleKey('c1'))!.extractBytes(), await (await b.keys.coupleKey('c1'))!.extractBytes());
    });

    test('a phone that cannot read is the only one allowed to start over', () async {
      await pairBoth();
      await expectLater(alice.repo.startFresh(), throwsA(isA<CryptoException>()));
      expect(server.startFreshCalls, 0);
      expect(await alice.keys.hasCoupleKey('c1'), isTrue);
    });

    test('a partner who still holds the old key takes the new one instead of sharing the old', () async {
      await pairBoth();
      final old = await coupleKeyOf(bob);
      await alice.keys.clearAll();
      final a = alice.newPhone();
      await a.repo.resetKeys();
      await a.repo.sync();
      await a.repo.markPartnerVerified(a.repo.current.securityCode!);
      expect(a.repo.current.phase, EncryptionPhase.needsApproval);

      await a.repo.startFresh();
      await bob.repo.sync();
      expect(bob.repo.current.phase, EncryptionPhase.partnerKeyChanged);
      await bob.repo.approvePartnerKey(bob.repo.current.securityCode!);

      expect(bob.repo.current.phase, EncryptionPhase.ready);
      expect(await coupleKeyOf(bob), isNot(old));
      expect(await coupleKeyOf(bob), await (await a.keys.coupleKey('c1'))!.extractBytes());
      expect((await a.repo.sync()).phase, EncryptionPhase.ready);
    });

    test('keys deleted on the server make a phone that still has the old one drop it and make a new one', () async {
      await pairBoth();
      final old = await coupleKeyOf(alice);
      server.coupleKeys.clear();

      expect((await alice.repo.sync()).phase, EncryptionPhase.ready);
      expect(await coupleKeyOf(alice), isNot(old));
      expect((await bob.repo.sync()).phase, EncryptionPhase.ready);
      expect(await coupleKeyOf(bob), await coupleKeyOf(alice));
    });
  });

  group('disconnecting and failures', () {
    test('leaving a couple forgets its key and what we remembered about the partner', () async {
      await pairBoth();
      expect(await alice.keys.hasCoupleKey('c1'), isTrue);

      alice.coupleId = null;
      alice.partnerId = null;
      final s = await alice.repo.sync();

      expect(s.phase, EncryptionPhase.noCouple);
      expect(await alice.keys.hasCoupleKey('c1'), isFalse);
      expect(await alice.keys.meta('partner.c1.key'), isNull);
      expect(await alice.keys.meta('partner.c1.verified'), isNull);
    });

    test('a new couple gets a new key, and needs its own confirmation', () async {
      await pairBoth();
      final old = await coupleKeyOf(alice);
      alice.coupleId = 'c2';
      bob.coupleId = 'c2';
      await alice.repo.sync();
      await bob.repo.sync();
      await alice.repo.sync();
      expect(alice.repo.current.phase, EncryptionPhase.needsVerification);
      await verifyBoth();
      expect(await (await alice.keys.coupleKey('c2'))!.extractBytes(), isNot(old));
      expect(await alice.keys.hasCoupleKey('c1'), isFalse);
    });

    test('no connection: the state is unknown, and no key is lost or replaced', () async {
      await pairBoth();
      final key = await coupleKeyOf(alice);
      final pub = await alice.keys.publicKeyBytes();

      server.offline = true;
      final s = await alice.repo.sync();

      expect(s.phase, EncryptionPhase.unknown);
      expect(await coupleKeyOf(alice), key);
      expect(await alice.keys.publicKeyBytes(), pub);

      server.offline = false;
      expect((await alice.repo.sync()).phase, EncryptionPhase.ready);
    });

    test('an action with no connection leaves the state unknown rather than throwing', () async {
      await exchangeKeys();
      server.offline = true;
      final s = await alice.repo.markPartnerVerified(alice.repo.current.securityCode!);
      expect(s.phase, EncryptionPhase.unknown);
    });
  });
}

/// What Alice would seal for Bob right now, to compare against the row on the server.
Future<String> _wrappedForBobNow(FakePhone alice, FakePhone bob) async {
  final crypto = CryptoService();
  return crypto.wrapKey(
    await (await alice.keys.coupleKey('c1'))!.extractBytes(),
    sender: await alice.keys.identityKeyPair(),
    recipientPublicKey: await bob.keys.publicKeyBytes(),
    aad: CryptoService.aadOf('couple-key', ['c1', '1', 'bob']),
  );
}
