import 'package:cryptography/cryptography.dart';

import 'crypto_service.dart';
import 'key_service.dart';

/// This phone does not have the couple's key (yet), so content cannot be encrypted or read.
/// Nothing is ever written unencrypted instead: the person finishes securing the connection first.
class EncryptionNotReady implements Exception {
  const EncryptionNotReady([this.message = 'Finish securing your connection first: Profile → Security.']);
  final String message;

  @override
  String toString() => message;
}

/// Encrypts and decrypts a couple's content with the couple key kept on this phone.
///
/// Every value is bound to its place (couple, table, row, field) by its associated data, so the
/// server cannot move ciphertext from one row, field or couple to another.
class ContentCipher {
  ContentCipher({required this.keysFor, required this.currentUserId, CryptoService? crypto}) : crypto = crypto ?? CryptoService();

  final KeyServiceFor       keysFor;
  /// The signed-in user, or null when nobody is signed in.
  final String? Function()  currentUserId;
  final CryptoService       crypto;

  Future<SecretKey> _key(String coupleId) async {
    final uid = currentUserId();
    if (uid == null) throw const EncryptionNotReady();
    final key = await keysFor(uid).coupleKey(coupleId);
    if (key == null) throw const EncryptionNotReady();
    return key;
  }

  /// Whether this phone can encrypt for [coupleId] right now.
  Future<bool> isReady(String coupleId) async {
    final uid = currentUserId();
    return uid != null && await keysFor(uid).hasCoupleKey(coupleId);
  }

  static bool isEncrypted(String? value) => value != null && value.startsWith(CryptoService.envelopePrefix);

  /// Seals [content] for one field of one row. Throws [EncryptionNotReady] without the couple key.
  Future<String> sealJson(Map<String, dynamic> content, {required String coupleId, required String table, required String rowId, String field = 'enc'}) async =>
      crypto.sealJson(content, key: await _key(coupleId), aad: CryptoService.fieldAad(coupleId: coupleId, table: table, rowId: rowId, field: field));

  /// Opens a value from [sealJson]. Throws [EncryptionNotReady] without the key, or [CryptoException]
  /// if it was not made for this place or was changed.
  Future<Map<String, dynamic>> openJson(String envelope, {required String coupleId, required String table, required String rowId, String field = 'enc'}) async =>
      crypto.openJson(envelope, key: await _key(coupleId), aad: CryptoService.fieldAad(coupleId: coupleId, table: table, rowId: rowId, field: field));

  Future<String> sealText(String text, {required String coupleId, required String table, required String rowId, String field = 'enc'}) async =>
      crypto.seal(text, key: await _key(coupleId), aad: CryptoService.fieldAad(coupleId: coupleId, table: table, rowId: rowId, field: field));

  Future<String> openText(String envelope, {required String coupleId, required String table, required String rowId, String field = 'enc'}) async =>
      crypto.open(envelope, key: await _key(coupleId), aad: CryptoService.fieldAad(coupleId: coupleId, table: table, rowId: rowId, field: field));
}
