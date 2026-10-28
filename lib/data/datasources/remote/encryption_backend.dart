import 'package:supabase_flutter/supabase_flutter.dart';

/// Everything the encryption logic asks of the server. The server only ever sees public keys and
/// values it cannot open (a backup sealed with the recovery phrase, keys sealed to a public key).
abstract interface class EncryptionBackend {
  /// The published public key (base64) of [userId]: our own, or our partner's. Null if none.
  Future<String?> publicKeyOf(String userId);
  Future<void>    publishPublicKey(String publicKeyBase64);

  /// This account's recovery backup (sealed with the recovery phrase), if any.
  Future<String?> fetchBackup();
  Future<void>    saveBackup(String backup);
  Future<void>    deleteBackup();

  /// The couple key sealed to our public key, if our partner has shared it.
  Future<String?> myWrappedKey(String coupleId, int version);

  /// Stores the first couple key, sealed for each partner ([wrappedByUser]: user id -> sealed key).
  /// Returns false, and writes nothing, if someone created it first.
  Future<bool> createCoupleKeys(String coupleId, int version, Map<String, String> wrappedByUser);

  /// Replaces the partner's sealed copy after approving their new public key.
  Future<void> replaceWrappedKey(String coupleId, int version, String userId, String wrapped);

  /// Deletes the couple's sealed content and keys (pictures first), so a new key can be made.
  Future<void> startFresh(String coupleId);
}

class SupabaseEncryptionBackend implements EncryptionBackend {
  SupabaseEncryptionBackend({required this.client});
  final SupabaseClient client;

  String get _me {
    final id = client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in');
    return id;
  }

  @override
  Future<String?> publicKeyOf(String userId) async {
    final row = await client.from('user_public_keys').select('public_key').eq('user_id', userId).maybeSingle();
    return row?['public_key'] as String?;
  }

  @override
  Future<void> publishPublicKey(String publicKeyBase64) =>
      client.rpc('publish_public_key', params: {'p_key': publicKeyBase64});

  @override
  Future<String?> fetchBackup() async {
    final row = await client.from('user_key_backups').select('backup').eq('user_id', _me).maybeSingle();
    return row?['backup'] as String?;
  }

  @override
  Future<void> saveBackup(String backup) =>
      client.from('user_key_backups').upsert({'user_id': _me, 'backup': backup, 'updated_at': DateTime.now().toUtc().toIso8601String()});

  @override
  Future<void> deleteBackup() => client.from('user_key_backups').delete().eq('user_id', _me);

  @override
  Future<String?> myWrappedKey(String coupleId, int version) async {
    final row = await client
        .from('couple_keys')
        .select('wrapped_key')
        .eq('couple_id', coupleId)
        .eq('user_id', _me)
        .eq('key_version', version)
        .maybeSingle();
    return row?['wrapped_key'] as String?;
  }

  @override
  Future<bool> createCoupleKeys(String coupleId, int version, Map<String, String> wrappedByUser) async {
    final created = await client.rpc('put_couple_keys', params: {
      'p_couple':  coupleId,
      'p_version': version,
      'p_rows':    wrappedByUser,
      'p_create':  true,
    });
    return created == true;
  }

  @override
  Future<void> replaceWrappedKey(String coupleId, int version, String userId, String wrapped) =>
      client.rpc('put_couple_keys', params: {
        'p_couple':  coupleId,
        'p_version': version,
        'p_rows':    {userId: wrapped},
        'p_create':  false,
      });

  @override
  Future<void> startFresh(String coupleId) async {
    // Sealed pictures are `<memory id>.enc`; SQL cannot remove Storage files, so the app does.
    final files = client.storage.from('memories');
    final objects = await files.list(path: coupleId, searchOptions: const SearchOptions(limit: 1000));
    final sealed = [for (final o in objects) if (o.name.endsWith('.enc')) '$coupleId/${o.name}'];
    if (sealed.isNotEmpty) await files.remove(sealed);
    await client.rpc('start_fresh_encryption', params: {'p_couple': coupleId});
  }
}
