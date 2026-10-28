/// Where secret keys live: the Android Keystore / iOS Keychain in the app (see
/// `FlutterSecureKeyStore`), an in-memory map in tests. Values are short strings.
abstract interface class SecureKeyStore {
  Future<String?> read(String key);
  Future<void>    write(String key, String value);
  Future<void>    delete(String key);
  /// Every stored key and value (used to find and wipe our own entries).
  Future<Map<String, String>> readAll();
}
