import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto_service.dart';
import 'secure_key_store.dart';

/// A random 256-bit key for THIS phone only, kept in the [SecureKeyStore] (Android Keystore / iOS Keychain).
/// It protects what the app stores on the phone itself: the cached server answers, the offline queue and
/// the pictures kept on the phone. It is not the couple key and is never sent anywhere; without it (a new
/// phone, or the app's data restored from a backup) those local files cannot be read, which is the point.
class DeviceKey {
  DeviceKey({required this.store, CryptoService? crypto}) : crypto = crypto ?? CryptoService();

  final SecureKeyStore store;
  final CryptoService  crypto;

  static const _storeKey = 'usync.local.v1';

  Future<Uint8List>? _bytes;

  /// The key's 32 bytes, created on first use. Concurrent callers share one creation.
  Future<Uint8List> bytes() => _bytes ??= _load();

  Future<Uint8List> _load() async {
    final existing = await store.read(_storeKey);
    if (existing != null) {
      try {
        final decoded = base64Decode(existing);
        if (decoded.length == CryptoService.keyLength) return Uint8List.fromList(decoded);
      } on FormatException {
        // falls through: an unreadable value is replaced (the local data it protected is a cache)
      }
    }
    final fresh = crypto.randomBytes(CryptoService.keyLength);
    await store.write(_storeKey, base64Encode(fresh));
    return fresh;
  }

  /// Forgets the in-memory copy after a failed load, so the next call tries again.
  void reset() => _bytes = null;

  /// Seals a local file's bytes, bound to its [name] so one file cannot be swapped for another.
  Future<Uint8List> sealFile(String name, List<int> plain) async =>
      crypto.sealBytes(plain, key: SecretKey(await bytes()), aad: CryptoService.aadOf('local-file', [name]));

  /// Opens bytes from [sealFile]. Throws [CryptoException] for a wrong key or a file that was changed.
  Future<Uint8List> openFile(String name, List<int> sealed) async =>
      crypto.openBytes(sealed, key: SecretKey(await bytes()), aad: CryptoService.aadOf('local-file', [name]));
}
