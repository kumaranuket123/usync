import 'package:usync/core/crypto/secure_key_store.dart';

/// A [SecureKeyStore] that keeps everything in a map, for tests.
class InMemoryKeyStore implements SecureKeyStore {
  InMemoryKeyStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<Map<String, String>> readAll() async => {...values};
}
