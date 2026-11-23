import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Private `chat` bucket: sealed photos and voice notes at `<couple_id>/<message id>.enc`. The
/// server only ever sees opaque bytes; the files are removed after the message expires.
class ChatMediaSource {
  ChatMediaSource({required this.client});
  final SupabaseClient client;

  StorageFileApi get _files => client.storage.from('chat');

  static String pathFor(String coupleId, String messageId) => '$coupleId/$messageId.enc';

  /// Replaces what is there, so repeating the upload after a lost connection leaves a single file.
  Future<void> upload(String path, Uint8List sealed) => _files.uploadBinary(
        path,
        sealed,
        fileOptions: const FileOptions(contentType: 'application/octet-stream', upsert: true),
      );

  Future<Uint8List> download(String path) => _files.download(path);
}
