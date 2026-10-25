import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Private `memories` bucket. Objects live at `<couple_id>/<uuid>.png`; the
/// storage RLS policy only lets active couple members touch their folder.
class StorageSource {
  StorageSource({required this.client});
  final SupabaseClient client;

  static const _bucket    = 'memories';
  static const _signedFor = 3600; // seconds
  final _uuid = const Uuid();

  StorageFileApi get _files => client.storage.from(_bucket);

  /// Uploads a PNG and returns its object path (what `memories.thumbnail_url` stores).
  Future<String> uploadPng(String coupleId, Uint8List bytes) async {
    final path = '$coupleId/${_uuid.v4()}.png';
    await _files.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/png'),
    );
    return path;
  }

  /// Maps object paths to short-lived signed URLs. Values that are already
  /// URLs (or empty) are left out of the result.
  Future<Map<String, String>> signedUrls(Iterable<String> paths) async {
    final unique = paths.where((p) => p.isNotEmpty && !p.startsWith('http')).toSet().toList();
    if (unique.isEmpty) return {};
    final results = await _files.createSignedUrlsResult(unique, _signedFor);
    return {
      for (final r in results)
        if (r is SignedUrlSuccess) r.path: r.signedUrl,
    };
  }

  Future<void> remove(String path) async {
    if (path.isEmpty || path.startsWith('http')) return;
    await _files.remove([path]);
  }
}
