import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/core/crypto/key_service.dart';

import 'in_memory_key_store.dart';

/// A [ContentCipher] for [userId] that already holds a couple key for each of [coupleIds].
/// Pass the same [coupleKey] to two ciphers to play two partners who share a key.
Future<ContentCipher> readyCipher({String userId = 'u1', List<String> coupleIds = const ['c1'], List<int>? coupleKey}) async {
  final store = InMemoryKeyStore();
  final keys = KeyService(store: store, namespace: userId);
  for (final id in coupleIds) {
    await keys.storeCoupleKey(id, coupleKey ?? await keys.newCoupleKeyBytes());
  }
  return ContentCipher(keysFor: (uid) => KeyService(store: store, namespace: uid), currentUserId: () => userId);
}

/// A [ContentCipher] with no couple key: this phone is not secured with its partner yet.
ContentCipher notReadyCipher({String userId = 'u1'}) {
  final store = InMemoryKeyStore();
  return ContentCipher(keysFor: (uid) => KeyService(store: store, namespace: uid), currentUserId: () => userId);
}

/// What a request carried, as one searchable string (to prove a secret never appears in it).
String bodyText(Object? json) => json.toString();
