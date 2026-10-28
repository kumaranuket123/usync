import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Something could not be encrypted, decrypted or parsed: a wrong key, changed data, or a malformed value.
class CryptoException implements Exception {
  const CryptoException(this.message);
  final String message;
  @override
  String toString() => 'CryptoException: $message';
}

/// The app's cryptography, with no storage and no state of its own.
///
/// - **Envelope**: `[version 1][nonce 12][ciphertext][tag 16]` from AES-256-GCM. As text it is
///   `u1:` + base64url. The associated data ([fieldAad]) ties a value to the row and field it
///   belongs to, so ciphertext copied to another row, field or couple no longer opens.
/// - **Key wrapping**: a key is sealed to someone's X25519 public key AND authenticated by the sender's
///   key (`w2:` + base64url): only the recipient can open it, and only the sender can have made it.
/// - **Recovery and security code**: helpers derived with HKDF / SHA-512.
///
/// Algorithms are looked up on every call, so the native implementation that the
/// `cryptography_flutter` plugin registers is used where it is available, and the pure-Dart one otherwise.
class CryptoService {
  CryptoService({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  static const envelopePrefix = 'u1:';
  static const wrapPrefix     = 'w2:';
  static const keyLength      = 32;

  static const _version     = 1;
  static const _nonceLength = 12;
  static const _macLength   = 16;

  AesGcm get _aes    => AesGcm.with256bits();
  X25519 get _x25519 => X25519();
  Hkdf   get _hkdf   => Hkdf(hmac: Hmac.sha256(), outputLength: keyLength);

  /// [length] cryptographically secure random bytes.
  Uint8List randomBytes(int length) => Uint8List.fromList(List<int>.generate(length, (_) => _random.nextInt(256)));

  /// A new random 256-bit key.
  SecretKey newSecretKey() => SecretKey(randomBytes(keyLength));

  /// Associated data for one field of one row: binds a value to its couple, table, row and field.
  static Uint8List fieldAad({
    required String coupleId,
    required String table,
    required String rowId,
    required String field,
  }) =>
      aadOf('field', [coupleId, table, rowId, field]);

  /// Associated data from free-form parts, for values that are not a table field (live messages,
  /// key wrapping, backups). Every part is length-prefixed, so two different lists of parts can
  /// never produce the same bytes, whatever characters they contain.
  static Uint8List aadOf(String purpose, [List<String> parts = const []]) {
    final out = BytesBuilder();
    for (final part in ['usync/v1', purpose, ...parts]) {
      final bytes = utf8.encode(part);
      out.add([(bytes.length >> 24) & 0xff, (bytes.length >> 16) & 0xff, (bytes.length >> 8) & 0xff, bytes.length & 0xff]);
      out.add(bytes);
    }
    return out.toBytes();
  }

  // ── Envelopes ────────────────────────────────────────────────────────────

  /// Encrypts [plaintext]; every call uses a fresh random nonce.
  Future<Uint8List> sealBytes(List<int> plaintext, {required SecretKey key, required List<int> aad}) async {
    final box = await _aes.encrypt(plaintext, secretKey: key, nonce: randomBytes(_nonceLength), aad: aad);
    final body = box.concatenation();
    return Uint8List(1 + body.length)
      ..[0] = _version
      ..setAll(1, body);
  }

  /// Decrypts an envelope from [sealBytes]. Throws [CryptoException] for a wrong key, wrong
  /// associated data, changed bytes or a malformed envelope.
  Future<Uint8List> openBytes(List<int> envelope, {required SecretKey key, required List<int> aad}) async {
    if (envelope.length < 1 + _nonceLength + _macLength) throw const CryptoException('The encrypted value is too short');
    if (envelope[0] != _version) throw CryptoException('Unknown encryption version ${envelope[0]}');
    try {
      final box = SecretBox.fromConcatenation(envelope.sublist(1), nonceLength: _nonceLength, macLength: _macLength);
      return Uint8List.fromList(await _aes.decrypt(box, secretKey: key, aad: aad));
    } on SecretBoxAuthenticationError {
      throw const CryptoException('Could not decrypt: wrong key, or the data was changed');
    } catch (_) {
      throw const CryptoException('Could not decrypt the value');
    }
  }

  bool isEnvelope(String value) => value.startsWith(envelopePrefix);

  Future<String> seal(String plaintext, {required SecretKey key, required List<int> aad}) async =>
      envelopePrefix + base64Url.encode(await sealBytes(utf8.encode(plaintext), key: key, aad: aad));

  Future<String> open(String envelope, {required SecretKey key, required List<int> aad}) async {
    final bytes = await openBytes(_decode(envelope, envelopePrefix), key: key, aad: aad);
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const CryptoException('The decrypted value is not text');
    }
  }

  Future<String> sealJson(Map<String, dynamic> json, {required SecretKey key, required List<int> aad}) =>
      seal(jsonEncode(json), key: key, aad: aad);

  Future<Map<String, dynamic>> openJson(String envelope, {required SecretKey key, required List<int> aad}) async {
    final text = await open(envelope, key: key, aad: aad);
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // falls through to the error below
    }
    throw const CryptoException('The decrypted value is not an object');
  }

  static Uint8List _decode(String value, String prefix) {
    if (!value.startsWith(prefix)) throw const CryptoException('Not an encrypted value');
    try {
      return base64Url.decode(base64Url.normalize(value.substring(prefix.length)));
    } on FormatException {
      throw const CryptoException('The encrypted value is malformed');
    }
  }

  // ── Key wrapping (authenticated, to someone's public key) ────────────────

  /// A fresh X25519 identity key pair from a 32-byte [seed] (so the seed can be stored or backed up).
  Future<SimpleKeyPair> keyPairFromSeed(List<int> seed) async {
    if (seed.length != keyLength) throw const CryptoException('A key seed must be 32 bytes');
    return _x25519.newKeyPairFromSeed(seed);
  }

  /// Seals [secret] so that only the owner of [recipientPublicKey] can open it, AND so that it can
  /// only have been made by the owner of [sender]: the sealing key mixes an ephemeral exchange with a
  /// static one between the two identities, so nobody who lacks the sender's private key (including
  /// the server) can produce a value the recipient will accept as coming from the sender.
  /// [aad] says what the key is for (couple, key version, recipient) and must match when opening.
  Future<String> wrapKey(List<int> secret, {required SimpleKeyPair sender, required List<int> recipientPublicKey, required List<int> aad}) async {
    if (recipientPublicKey.length != keyLength) throw const CryptoException('A public key must be 32 bytes');
    final ephemeral    = await _x25519.newKeyPairFromSeed(randomBytes(keyLength));
    final ephemeralPub = (await ephemeral.extractPublicKey()).bytes;
    final senderPub    = (await sender.extractPublicKey()).bytes;
    final wrapping = await _wrappingKey(
      ephemeralShared: await _dh(ephemeral, recipientPublicKey),
      staticShared:    await _dh(sender, recipientPublicKey),
      ephemeralPub: ephemeralPub,
      senderPub: senderPub,
      recipientPub: recipientPublicKey,
    );
    final sealed = await sealBytes(secret, key: wrapping, aad: [...aad, ...ephemeralPub]);
    return wrapPrefix + base64Url.encode([...ephemeralPub, ...sealed]);
  }

  /// Opens a key from [wrapKey] with our identity [recipient], accepting it only if it was made by
  /// the owner of [senderPublicKey]. Throws [CryptoException] otherwise: a value made by anyone else,
  /// including a server that knows our public key, does not open.
  Future<Uint8List> unwrapKey(String wrapped, {required SimpleKeyPair recipient, required List<int> senderPublicKey, required List<int> aad}) async {
    if (senderPublicKey.length != keyLength) throw const CryptoException('A public key must be 32 bytes');
    final bytes = _decode(wrapped, wrapPrefix);
    if (bytes.length < keyLength + 1 + _nonceLength + _macLength) throw const CryptoException('The wrapped key is too short');
    final ephemeralPub = bytes.sublist(0, keyLength);
    final myPublic     = (await recipient.extractPublicKey()).bytes;
    final wrapping = await _wrappingKey(
      ephemeralShared: await _dh(recipient, ephemeralPub),
      staticShared:    await _dh(recipient, senderPublicKey),
      ephemeralPub: ephemeralPub,
      senderPub: senderPublicKey,
      recipientPub: myPublic,
    );
    return openBytes(bytes.sublist(keyLength), key: wrapping, aad: [...aad, ...ephemeralPub]);
  }

  /// X25519 between our key pair and a public key. An all-zero result means the other key was a
  /// low-order point, which is refused.
  Future<List<int>> _dh(SimpleKeyPair mine, List<int> theirPublic) async {
    try {
      final shared = await _x25519.sharedSecretKey(keyPair: mine, remotePublicKey: SimplePublicKey(theirPublic, type: KeyPairType.x25519));
      final bytes = await shared.extractBytes();
      if (bytes.every((b) => b == 0)) throw const CryptoException('Rejected an invalid public key');
      return bytes;
    } on CryptoException {
      rethrow;
    } catch (_) {
      throw const CryptoException('Rejected an invalid public key');
    }
  }

  Future<SecretKey> _wrappingKey({
    required List<int> ephemeralShared,
    required List<int> staticShared,
    required List<int> ephemeralPub,
    required List<int> senderPub,
    required List<int> recipientPub,
  }) =>
      _hkdf.deriveKey(
        secretKey: SecretKey([...ephemeralShared, ...staticShared]),
        nonce: [...ephemeralPub, ...senderPub, ...recipientPub],
        info: utf8.encode('usync/wrap/v2'),
      );

  // ── Recovery ─────────────────────────────────────────────────────────────

  /// The key that protects the identity-key backup, from the entropy behind the recovery phrase.
  Future<SecretKey> backupKeyFromEntropy(List<int> entropy) => _hkdf.deriveKey(
        secretKey: SecretKey(entropy),
        nonce: utf8.encode('usync/recovery/salt/v1'),
        info: utf8.encode('usync/recovery-backup/v1'),
      );

  // ── Security code ────────────────────────────────────────────────────────

  /// Sixty digits (12 groups of 5) that both partners compute from their two public keys and
  /// compare out loud. The same for both of them; different if either key was swapped.
  Future<String> securityCode(List<int> publicKeyA, List<int> publicKeyB) async {
    final ordered = _compare(publicKeyA, publicKeyB) <= 0 ? [publicKeyA, publicKeyB] : [publicKeyB, publicKeyA];
    final hash = (await Sha512().hash([...utf8.encode('usync/security-code/v1'), ...ordered[0], ...ordered[1]])).bytes;
    final groups = <String>[];
    for (var i = 0; i < 12; i++) {
      var value = 0;
      for (var j = 0; j < 5; j++) {
        value = (value << 8) | hash[i * 5 + j];
      }
      groups.add((value % 100000).toString().padLeft(5, '0'));
    }
    return groups.join(' ');
  }

  static int _compare(List<int> a, List<int> b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return a.length.compareTo(b.length);
  }
}
