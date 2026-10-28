import 'package:usync/core/crypto/key_service.dart';
import 'package:usync/data/datasources/remote/encryption_backend.dart';
import 'package:usync/data/repositories/encryption_context.dart';
import 'package:usync/data/repositories/encryption_repository.dart';

import 'in_memory_key_store.dart';

/// A server that keeps only what the real one keeps: public keys, recovery backups and sealed couple keys.
class FakeEncryptionServer {
  final publicKeys = <String, String>{};
  final backups = <String, String>{};
  final coupleKeys = <String, Map<String, String>>{};
  var publishCalls = 0;
  var startFreshCalls = 0;
  var offline = false;

  EncryptionBackend as(String userId) => _Backend(this, userId);

  void _check() {
    if (offline) throw Exception('offline');
  }
}

class _Backend implements EncryptionBackend {
  _Backend(this.server, this.me);
  final FakeEncryptionServer server;
  final String me;

  String _k(String couple, int version) => '$couple|$version';

  @override
  Future<String?> publicKeyOf(String userId) async {
    server._check();
    return server.publicKeys[userId];
  }

  @override
  Future<void> publishPublicKey(String publicKeyBase64) async {
    server._check();
    server.publishCalls++;
    server.publicKeys[me] = publicKeyBase64;
  }

  @override
  Future<String?> fetchBackup() async {
    server._check();
    return server.backups[me];
  }

  @override
  Future<void> saveBackup(String backup) async {
    server._check();
    server.backups[me] = backup;
  }

  @override
  Future<void> deleteBackup() async {
    server._check();
    server.backups.remove(me);
  }

  @override
  Future<String?> myWrappedKey(String coupleId, int version) async {
    server._check();
    return server.coupleKeys[_k(coupleId, version)]?[me];
  }

  @override
  Future<bool> createCoupleKeys(String coupleId, int version, Map<String, String> wrappedByUser) async {
    server._check();
    if (server.coupleKeys.containsKey(_k(coupleId, version))) return false;
    server.coupleKeys[_k(coupleId, version)] = {...wrappedByUser};
    return true;
  }

  @override
  Future<void> replaceWrappedKey(String coupleId, int version, String userId, String wrapped) async {
    server._check();
    if (userId == me) throw Exception('You cannot replace your own key');
    server.coupleKeys[_k(coupleId, version)]![userId] = wrapped;
  }

  @override
  Future<void> startFresh(String coupleId) async {
    server._check();
    server.startFreshCalls++;
    server.coupleKeys.removeWhere((key, _) => key.startsWith('$coupleId|'));
  }
}

/// One signed-in phone: its own key store, its own view of who the partner is.
class FakePhone implements EncryptionContextSource {
  FakePhone(this.server, this.userId, {this.coupleId, this.partnerId, InMemoryKeyStore? store})
      : store = store ?? InMemoryKeyStore() {
    repo = EncryptionRepository(
      backend: server.as(userId),
      context: this,
      keysFor: (uid) => KeyService(store: this.store, namespace: uid),
    );
  }

  final FakeEncryptionServer server;
  final String userId;
  String? coupleId;
  String? partnerId;
  final InMemoryKeyStore store;
  late final EncryptionRepository repo;

  KeyService get keys => KeyService(store: store, namespace: userId);

  @override
  Future<EncryptionContext?> current() async => (userId: userId, coupleId: coupleId, partnerId: partnerId);

  /// The same account on a different phone (empty key store).
  FakePhone newPhone() => FakePhone(server, userId, coupleId: coupleId, partnerId: partnerId);
}
