import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../core/crypto/crypto_service.dart';
import '../../core/crypto/key_service.dart';
import '../../domain/entities/encryption_state.dart';
import '../../domain/repositories/i_encryption_repository.dart';
import '../datasources/remote/encryption_backend.dart';
import 'encryption_context.dart';

/// Runs the key protocol: publish our public key, share the couple's key with the partner, notice
/// a partner whose keys changed, and recover keys on a new phone.
///
/// The rules that keep it safe against a server that tries to interfere:
/// - **Nothing is shared or accepted before a person has compared the security code.** The couple's
///   key is created or adopted only once the code for the partner's current key was confirmed, so a
///   partner key swapped by the server cannot be handed the couple's key.
/// - **Wrapped keys are authenticated.** A key is accepted only if it was made by us or by the partner
///   whose key we confirmed, so the server cannot choose the couple's key even though it can write rows.
/// - A confirmation applies to the exact code the person saw, never to whatever the server serves later.
/// - A partner's changed key is never trusted automatically: the person must compare and approve.
/// - A phone that has no key but whose account already has one published never makes a new key by
///   itself: it asks to restore. A phone only (re)publishes a key it made itself.
/// - Every operation runs one at a time, so two of them can never interleave.
class EncryptionRepository implements IEncryptionRepository {
  EncryptionRepository({required this.backend, required this.context, required this.keysFor});

  final EncryptionBackend       backend;
  final EncryptionContextSource context;
  final KeyServiceFor           keysFor;

  static const _coupleKeyVersion = 1;

  EncryptionState _last = const EncryptionState.unknown();
  Future<EncryptionState>? _running;
  Future<void> _tail = Future<void>.value();

  @override
  EncryptionState get current => _last;

  /// Runs [action] after everything queued before it has finished.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<EncryptionState> sync() {
    // Two callers at once share one run.
    return _running ??= _exclusive(() => _guarded(_sync)).whenComplete(() => _running = null);
  }

  Future<EncryptionState> _guarded(Future<EncryptionState> Function() run) async {
    try {
      return _last = await run();
    } on CryptoException {
      rethrow;
    } catch (e) {
      debugPrint('Encryption sync could not finish: ${e.runtimeType}');
      return _last = _last.copyWith(phase: EncryptionPhase.unknown);
    }
  }

  /// A person-facing operation: a [CryptoException] (wrong code, wrong phrase) reaches the caller,
  /// anything else (no connection) just leaves the state as unknown.
  Future<EncryptionState> _operation(Future<EncryptionState> Function() run) => _exclusive(() async {
        try {
          return _last = await run();
        } on CryptoException {
          rethrow;
        } catch (e) {
          debugPrint('Encryption operation could not finish: ${e.runtimeType}');
          return _last = _last.copyWith(phase: EncryptionPhase.unknown);
        }
      });

  static Uint8List? _validKey(String? b64) {
    if (b64 == null) return null;
    try {
      final bytes = base64Decode(b64);
      return bytes.length == CryptoService.keyLength ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  static Uint8List _wrapAad(String coupleId, String recipientId) =>
      CryptoService.aadOf('couple-key', [coupleId, '$_coupleKeyVersion', recipientId]);

  static String _seenName(String coupleId) => 'partner.$coupleId.key';
  static String _verifiedName(String coupleId) => 'partner.$coupleId.verified';

  // ── The protocol ─────────────────────────────────────────────────────────

  Future<EncryptionState> _sync() async {
    final ctx = await context.current();
    if (ctx == null) return const EncryptionState.unknown();
    final keys = keysFor(ctx.userId);
    final crypto = keys.crypto;

    // Forget a couple we are no longer in.
    final lastCouple = await keys.meta('couple');
    if (lastCouple != null && lastCouple != ctx.coupleId) {
      await keys.forgetCouple(lastCouple);
      await keys.deleteMeta('couple');
    }

    final published = await backend.publicKeyOf(ctx.userId);
    final recoverySetUp = await keys.meta('recovery') == '1';
    EncryptionState state(EncryptionPhase phase, {String? code, bool verified = false, String? coupleId}) => EncryptionState(
          phase: phase, securityCode: code, partnerVerified: verified, recoverySetUp: recoverySetUp, coupleId: coupleId);

    if (!await keys.hasIdentity()) {
      if (published != null) return state(EncryptionPhase.needsRestore, coupleId: ctx.coupleId);
      await keys.createIdentity(); // first time for this account
      await keys.setMeta('publishPending', '1');
    }

    final myPair = await keys.identityKeyPair();
    final myPublic = Uint8List.fromList((await myPair.extractPublicKey()).bytes);
    final myPublicB64 = base64Encode(myPublic);
    if (published == null || await keys.meta('publishPending') == '1') {
      await backend.publishPublicKey(myPublicB64);
      await keys.deleteMeta('publishPending');
    } else if (published != myPublicB64) {
      // Another phone of this account made a different key. Do not fight it: ask to restore.
      return state(EncryptionPhase.needsRestore, coupleId: ctx.coupleId);
    }

    final coupleId = ctx.coupleId;
    final partnerId = ctx.partnerId;
    if (coupleId == null || partnerId == null) return state(EncryptionPhase.noCouple);
    await keys.setMeta('couple', coupleId);

    final partnerPublicB64 = await backend.publicKeyOf(partnerId);
    final partnerPublic = _validKey(partnerPublicB64);
    if (partnerPublic == null) return state(EncryptionPhase.waitingForPartner, coupleId: coupleId);

    final code = await crypto.securityCode(myPublic, partnerPublic);
    var hasKey = await keys.hasCoupleKey(coupleId, version: _coupleKeyVersion);
    final verified = await keys.meta(_verifiedName(coupleId)) == code;
    final seen = await keys.meta(_seenName(coupleId));

    // We hold the key and the partner's key is not the one we accepted: a person must decide.
    if (hasKey && seen != null && seen != partnerPublicB64) {
      return state(EncryptionPhase.partnerKeyChanged, code: code, coupleId: coupleId);
    }
    // Nothing is shared or accepted until the code for this exact pair of keys was confirmed.
    if (!verified) return state(EncryptionPhase.needsVerification, code: code, coupleId: coupleId);

    // Keep the key we hold in step with the server's copy. If the couple started fresh, the server has
    // none (ours opens nothing any more) or a new one from the partner we confirmed.
    if (hasKey && await _adoptSharedKey(keys, myPair, myPublic, partnerPublic, ctx.userId, coupleId) == _Adopt.none) {
      await keys.forgetCouple(coupleId);
      hasKey = false;
    }

    if (!hasKey) {
      var adopted = await _adoptSharedKey(keys, myPair, myPublic, partnerPublic, ctx.userId, coupleId);
      if (adopted == _Adopt.none) {
        final created = await _createKey(keys, myPair, ctx.userId, coupleId, partnerId, partnerPublic);
        if (!created) adopted = await _adoptSharedKey(keys, myPair, myPublic, partnerPublic, ctx.userId, coupleId);
      }
      if (adopted == _Adopt.cannotOpen) return state(EncryptionPhase.needsApproval, code: code, verified: true, coupleId: coupleId);
      if (!await keys.hasCoupleKey(coupleId, version: _coupleKeyVersion)) {
        return state(EncryptionPhase.waitingForKey, code: code, verified: true, coupleId: coupleId);
      }
    }

    if (seen != partnerPublicB64) await keys.setMeta(_seenName(coupleId), partnerPublicB64!); // non-null: it decoded to a valid key above
    return state(EncryptionPhase.ready, code: code, verified: true, coupleId: coupleId);
  }

  /// Takes the couple's key the server holds for us, if it was made by us or by the partner we confirmed.
  Future<_Adopt> _adoptSharedKey(KeyService keys, SimpleKeyPair myPair, Uint8List myPublic, Uint8List partnerPublic, String userId, String coupleId) async {
    final wrapped = await backend.myWrappedKey(coupleId, _coupleKeyVersion);
    if (wrapped == null) return _Adopt.none;
    for (final sender in [partnerPublic, myPublic]) {
      try {
        final key = await keys.crypto.unwrapKey(wrapped, recipient: myPair, senderPublicKey: sender, aad: _wrapAad(coupleId, userId));
        await keys.storeCoupleKey(coupleId, key, version: _coupleKeyVersion);
        return _Adopt.adopted;
      } catch (_) {
        // not made by this sender: try the next one
      }
    }
    // Made by neither of us (an older key of ours, or someone else): the partner must approve.
    return _Adopt.cannotOpen;
  }

  /// Makes the couple's key and seals it, authenticated by us, for both of us. False if someone created it first.
  Future<bool> _createKey(KeyService keys, SimpleKeyPair myPair, String userId, String coupleId, String partnerId, Uint8List partnerPublic) async {
    final key = await keys.newCoupleKeyBytes();
    final mine = await keys.crypto.wrapKey(key, sender: myPair, recipientPublicKey: (await myPair.extractPublicKey()).bytes, aad: _wrapAad(coupleId, userId));
    final theirs = await keys.crypto.wrapKey(key, sender: myPair, recipientPublicKey: partnerPublic, aad: _wrapAad(coupleId, partnerId));
    final created = await backend.createCoupleKeys(coupleId, _coupleKeyVersion, {userId: mine, partnerId: theirs});
    if (created) await keys.storeCoupleKey(coupleId, key, version: _coupleKeyVersion);
    return created;
  }

  // ── Person-facing operations ─────────────────────────────────────────────

  /// The code for the partner's key as the server serves it right now, or throws if it is not [expected].
  Future<({EncryptionContext ctx, KeyService keys, String partnerPublicB64})> _checkedPartner(String expectedCode) async {
    final ctx = await context.current();
    final coupleId = ctx?.coupleId;
    final partnerId = ctx?.partnerId;
    if (ctx == null || coupleId == null || partnerId == null) throw const CryptoException('You are not paired');
    final keys = keysFor(ctx.userId);
    final partnerPublicB64 = await backend.publicKeyOf(partnerId);
    final partnerPublic = _validKey(partnerPublicB64);
    if (partnerPublic == null) throw const CryptoException('Your partner has no keys yet');
    final code = await keys.crypto.securityCode(await keys.publicKeyBytes(), partnerPublic);
    if (code != expectedCode) {
      throw const CryptoException('The security code changed while you were looking at it. Compare the new code.');
    }
    return (ctx: ctx, keys: keys, partnerPublicB64: partnerPublicB64!);
  }

  @override
  Future<EncryptionState> markPartnerVerified(String securityCode) => _operation(() async {
        final c = await _checkedPartner(securityCode);
        final coupleId = c.ctx.coupleId!;
        await c.keys.setMeta(_verifiedName(coupleId), securityCode);
        // The first time, accepting the code also accepts the key. A key that CHANGED after we
        // already held the couple's key needs an explicit approval instead.
        if (await c.keys.meta(_seenName(coupleId)) == null) await c.keys.setMeta(_seenName(coupleId), c.partnerPublicB64);
        return _sync();
      });

  @override
  String newRecoveryPhrase() => KeyService.newRecoveryPhrase();

  @override
  Future<EncryptionState> finishRecovery(String phrase) => _operation(() async {
        final ctx = await context.current();
        if (ctx == null) return _last;
        final keys = keysFor(ctx.userId);
        if (!await keys.hasIdentity()) throw const CryptoException('There are no keys to back up yet');
        await backend.saveBackup(await keys.backupIdentity(phrase));
        await keys.setMeta('recovery', '1');
        return _sync();
      });

  @override
  Future<EncryptionState> restoreWithPhrase(String phrase) => _operation(() async {
        final ctx = await context.current();
        if (ctx == null) return _last;
        final keys = keysFor(ctx.userId);
        final backup = await backend.fetchBackup();
        if (backup == null) throw const CryptoException('There is no recovery backup for this account');
        final published = await backend.publicKeyOf(ctx.userId);

        // Open and compare BEFORE writing anything, so a wrong or outdated phrase (or an old backup the
        // server kept) can never replace or wipe the keys that are on this phone.
        final seed = await keys.openIdentityBackup(phrase: phrase, backup: backup);
        final restored = base64Encode((await (await keys.crypto.keyPairFromSeed(seed)).extractPublicKey()).bytes);
        if (published != null && restored != published) {
          throw const CryptoException('This recovery phrase does not match the current keys of this account');
        }
        await keys.installIdentity(seed);
        await keys.setMeta('recovery', '1');
        return _sync();
      });

  @override
  Future<EncryptionState> resetKeys() => _operation(() async {
        final ctx = await context.current();
        if (ctx == null) return _last;
        final keys = keysFor(ctx.userId);
        await keys.resetIdentity();
        await keys.deleteMeta('recovery');
        await keys.setMeta('publishPending', '1');
        await backend.deleteBackup();
        return _sync();
      });

  @override
  Future<EncryptionState> startFresh() => _operation(() async {
        final ctx = await context.current();
        final coupleId = ctx?.coupleId;
        if (ctx == null || coupleId == null) throw const CryptoException('You are not paired');
        // Only for a phone that cannot get the key: never for one that can still read the history.
        final phase = (await _sync()).phase;
        if (phase != EncryptionPhase.needsApproval && phase != EncryptionPhase.waitingForKey) {
          throw const CryptoException('Nothing to start over: this phone is not stuck.');
        }
        await backend.startFresh(coupleId);
        return _sync();
      });

  @override
  Future<EncryptionState> approvePartnerKey(String securityCode) => _operation(() async {
        final c = await _checkedPartner(securityCode);
        final coupleId = c.ctx.coupleId!;
        final partnerId = c.ctx.partnerId!;
        final seen = await c.keys.meta(_seenName(coupleId));
        if (seen == c.partnerPublicB64) return _sync(); // nothing to approve
        // Never share a key the server no longer holds: the couple may have started fresh meanwhile.
        final myPair = await c.keys.identityKeyPair();
        final myPublic = Uint8List.fromList((await myPair.extractPublicKey()).bytes);
        if (await _adoptSharedKey(c.keys, myPair, myPublic, base64Decode(c.partnerPublicB64), c.ctx.userId, coupleId) == _Adopt.none) {
          await c.keys.forgetCouple(coupleId);
          return _sync();
        }
        final couple = await c.keys.coupleKey(coupleId, version: _coupleKeyVersion);
        if (couple == null) throw const CryptoException('This phone does not have the couple key to share');
        final wrapped = await c.keys.crypto.wrapKey(
          await couple.extractBytes(),
          sender: await c.keys.identityKeyPair(),
          recipientPublicKey: base64Decode(c.partnerPublicB64),
          aad: _wrapAad(coupleId, partnerId),
        );
        await backend.replaceWrappedKey(coupleId, _coupleKeyVersion, partnerId, wrapped);
        await c.keys.setMeta(_seenName(coupleId), c.partnerPublicB64);
        await c.keys.setMeta(_verifiedName(coupleId), securityCode);
        return _sync();
      });
}

enum _Adopt { none, adopted, cannotOpen }
