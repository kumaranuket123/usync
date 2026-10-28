import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Private `memories` bucket. Objects live at `<couple_id>/<memory id>.enc` (older ones `<uuid>.png`); the
/// storage RLS policy only lets active couple members touch their folder.
class StorageSource {
  StorageSource({required this.client});
  final SupabaseClient client;

  static const _bucket    = 'memories';

  StorageFileApi get _files => client.storage.from(_bucket);

  /// Uploads an already-encrypted picture to a path chosen by the caller, replacing what is there, so
  /// repeating the upload after a lost connection leaves a single file. The server only ever sees
  /// opaque bytes.
  Future<void> uploadSealedAt(String path, Uint8List sealed) => _files.uploadBinary(
        path,
        sealed,
        fileOptions: const FileOptions(contentType: 'application/octet-stream', upsert: true),
      );

  /// Deletes every image of a couple. Only an active member may, so this has to
  /// run before the couple is disconnected.
  Future<void> removeFolder(String coupleId) async {
    final objects = await _files.list(path: coupleId, searchOptions: const SearchOptions(limit: 1000));
    if (objects.isEmpty) return;
    await _files.remove([for (final o in objects) '$coupleId/${o.name}']);
  }

  Future<Uint8List> download(String path) => _files.download(path);

  Future<void> remove(String path) async {
    if (path.isEmpty || path.startsWith('http')) return;
    await _files.remove([path]);
  }
}
