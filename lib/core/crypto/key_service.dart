import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:cryptography/cryptography.dart';

import 'crypto_service.dart';
import 'secure_key_store.dart';

/// Our keys: the identity key pair, one key per couple, and the recovery phrase.
///
/// Everything is stored under a per-account [namespace] (the user id), so two accounts on one
/// phone never see each other's keys, and signing out and back in keeps the keys.
///
/// It needs only a [SecureKeyStore], never the service locator, so it can also run in a
/// background isolate (a "locate" request or the home-screen widget). Secrets are never
/// written anywhere else, and never logged.
class KeyService {
  KeyService({required SecureKeyStore store, CryptoService? crypto, String namespace = ''})
      : _store = store,
        crypto = crypto ?? CryptoService(),
        _namespace = namespace.isEmpty ? 'default' : namespace,
        _prefix = 'e2ee.${namespace.isEmpty ? 'default' : namespace}.';

  final SecureKeyStore _store;
  final CryptoService  crypto;

  final String _prefix;

  final String _namespace;

  /// Binds a backup to its account, so a backup cannot be moved to another account's row.
  List<int> get _backupAad => CryptoService.aadOf('identity-backup', [_namespace]);

  String get _identityKey => '${_prefix}identity.seed.v1';
  String _coupleKeyName(String coupleId, int version) => '${_prefix}couple.$coupleId.v$version';
  String _metaName(String name) => '${_prefix}meta.$name';

  // ── Small flags (not secret, but kept with the keys so they are wiped with them) ──

  Future<String?> meta(String name) => _store.read(_metaName(name));
  Future<void>    setMeta(String name, String value) => _store.write(_metaName(name), value);
  Future<void>    deleteMeta(String name) => _store.delete(_metaName(name));

  // ── Identity ─────────────────────────────────────────────────────────────

  Future<bool> hasIdentity() async => (await _store.read(_identityKey)) != null;

  /// Makes this account's identity key if there is none, and returns it. This is the ONLY place a
  /// key is ever made: everything else only reads the existing one, so no code path (a background
  /// task, a race) can silently replace an identity.
  Future<SimpleKeyPair> createIdentity() async {
    var seed = await _store.read(_identityKey);
    if (seed == null) {
      seed = base64Encode(crypto.randomBytes(CryptoService.keyLength));
      await _store.write(_identityKey, seed);
    }
    return crypto.keyPairFromSeed(base64Decode(seed));
  }

  /// The existing identity key pair. Throws [CryptoException] if there is none.
  Future<SimpleKeyPair> identityKeyPair() async {
    final seed = await _store.read(_identityKey);
    if (seed == null) throw const CryptoException('There is no identity key on this phone');
    return crypto.keyPairFromSeed(base64Decode(seed));
  }

  /// Our public key (32 bytes), safe to share. Throws [CryptoException] if there is no identity.
  Future<Uint8List> publicKeyBytes() async =>
      Uint8List.fromList((await (await identityKeyPair()).extractPublicKey()).bytes);

  /// Throws the current identity away and makes a new one (the partner must approve it).
  Future<void> resetIdentity() async {
    await _store.delete(_identityKey);
    await createIdentity();
  }

  /// Puts a known identity [seed] in place (restoring from a backup).
  Future<void> installIdentity(List<int> seed) async {
    if (seed.length != CryptoService.keyLength) throw const CryptoException('The key is damaged');
    await _store.write(_identityKey, base64Encode(seed));
  }

  // ── Couple keys ──────────────────────────────────────────────────────────

  Future<bool> hasCoupleKey(String coupleId, {int version = 1}) async =>
      (await _store.read(_coupleKeyName(coupleId, version))) != null;

  /// The couple's key, or null if this phone does not have it (yet).
  Future<SecretKey?> coupleKey(String coupleId, {int version = 1}) async {
    final stored = await _store.read(_coupleKeyName(coupleId, version));
    return stored == null ? null : SecretKey(base64Decode(stored));
  }

  Future<void> storeCoupleKey(String coupleId, List<int> keyBytes, {int version = 1}) async {
    if (keyBytes.length != CryptoService.keyLength) throw const CryptoException('A couple key must be 32 bytes');
    await _store.write(_coupleKeyName(coupleId, version), base64Encode(keyBytes));
  }

  /// A new random couple key. It is not stored: wrap it for both partners first.
  Future<Uint8List> newCoupleKeyBytes() async => Uint8List.fromList(await crypto.newSecretKey().extractBytes());

  // ── Recovery phrase ──────────────────────────────────────────────────────

  /// A new 12-word recovery phrase (128 bits of randomness).
  static String newRecoveryPhrase() =>
      Mnemonic.generate(Language.english, length: MnemonicLength.words12).sentence;

  /// Lower-case, single-spaced, so a phrase typed with capitals or extra spaces still works.
  static String normalizePhrase(String phrase) => phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

  /// Whether [phrase] is 12 valid words with a correct checksum.
  static bool isValidPhrase(String phrase) {
    try {
      final m = Mnemonic.fromSentence(normalizePhrase(phrase), Language.english);
      return m.length == MnemonicLength.words12;
    } catch (_) {
      return false;
    }
  }

  Future<SecretKey> _backupKey(String phrase) async {
    if (!isValidPhrase(phrase)) throw const CryptoException('That is not a valid 12-word recovery phrase');
    final entropy = Mnemonic.fromSentence(normalizePhrase(phrase), Language.english).entropy;
    return crypto.backupKeyFromEntropy(entropy);
  }

  /// The identity key sealed with the recovery phrase: safe to store on the server, because
  /// without the phrase it cannot be opened.
  Future<String> backupIdentity(String phrase) async {
    final key  = await _backupKey(phrase);
    final seed = base64Decode((await _store.read(_identityKey)) ?? (throw const CryptoException('There is no identity key to back up')));
    return crypto.seal(base64Encode(seed), key: key, aad: _backupAad);
  }

  /// Opens [backup] with the recovery [phrase] and returns the identity seed, WITHOUT storing it, so
  /// the caller can check it first. Throws [CryptoException] for a wrong phrase or a damaged backup.
  Future<Uint8List> openIdentityBackup({required String phrase, required String backup}) async {
    final key   = await _backupKey(phrase);
    final seed  = await crypto.open(backup, key: key, aad: _backupAad);
    try {
      final bytes = base64Decode(seed);
      if (bytes.length == CryptoService.keyLength) return bytes;
    } on FormatException {
      // falls through to the error below
    }
    throw const CryptoException('The backup is damaged');
  }

  /// Opens [backup] and puts the identity key on this phone in one step.
  Future<void> restoreIdentity({required String phrase, required String backup}) async =>
      installIdentity(await openIdentityBackup(phrase: phrase, backup: backup));

  // ── Wiping ───────────────────────────────────────────────────────────────

  /// Forgets one couple's key and what we remembered about the partner (when the couple disconnects).
  Future<void> forgetCouple(String coupleId) async {
    final all = await _store.readAll();
    final prefixes = ['${_prefix}couple.$coupleId.', '${_prefix}meta.partner.$coupleId.'];
    for (final name in all.keys.where((k) => prefixes.any(k.startsWith))) {
      await _store.delete(name);
    }
  }

  /// Wipes everything this account holds on this phone (account deletion).
  Future<void> clearAll() async {
    final all = await _store.readAll();
    for (final name in all.keys.where((k) => k.startsWith(_prefix))) {
      await _store.delete(name);
    }
  }
}
