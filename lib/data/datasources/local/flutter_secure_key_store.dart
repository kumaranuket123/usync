import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/crypto/secure_key_store.dart';

/// [SecureKeyStore] on the Android Keystore / iOS Keychain. Keys never leave the phone: they are
/// not backed up (Android backup is off) and the Keychain items stay on this device.
class FlutterSecureKeyStore implements SecureKeyStore {
  const FlutterSecureKeyStore([this._storage = const FlutterSecureStorage(
    // Never wipe the stored keys because of a Keystore hiccup: the plugin's default (resetOnError)
    // would silently delete them. A read error is reported as an error instead.
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  )]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}
