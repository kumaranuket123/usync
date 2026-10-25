import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/signed_url_cache.dart';

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

  /// Uploads a PNG to a path chosen by the caller, replacing what is there, so
  /// repeating the upload after a lost connection leaves a single file.
  Future<void> uploadPngAt(String path, Uint8List bytes) => _files.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
      );

  final _cache = SignedUrlCache(lifetime: const Duration(seconds: _signedFor));

  /// Maps object paths to short-lived signed URLs. Values that are already
  /// URLs (or empty) are left out of the result. Links are remembered until
  /// shortly before they expire, so a list that changes often (a favourite
  /// toggled, a new memory) only signs what is actually new.
  Future<Map<String, String>> signedUrls(Iterable<String> paths) {
    final wanted = paths.where((p) => p.isNotEmpty && !p.startsWith('http'));
    return _cache.resolve(wanted, (missing) async {
      final results = await _files.createSignedUrlsResult(missing, _signedFor);
      return {
        for (final r in results)
          if (r is SignedUrlSuccess) r.path: r.signedUrl,
      };
    });
  }

  Future<void> remove(String path) async {
    if (path.isEmpty || path.startsWith('http')) return;
    await _files.remove([path]);
  }
}
