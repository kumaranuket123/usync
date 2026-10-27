import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pictures of older memories, kept on the phone after they are removed from the
/// server (see `MemoryRepository.archiveOlderImages`). One PNG per memory id in
/// the app's own `usync/memories` folder.
///
/// Kept per signed-in user (`usync/memories/<user id>/`): the next person to
/// sign in on this phone never sees them or touches them, and they are still
/// here when their owner signs back in.
abstract final class LocalMemoryImages {
  static Future<Directory?> _root() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/usync/memories/$uid').create(recursive: true);
  }

  static Future<File?> _file(String id) async {
    final root = await _root();
    return root == null ? null : File('${root.path}/$id.png');
  }

  /// The saved picture's path, or null when this phone has none.
  static Future<String?> pathIfExists(String id) async {
    final file = await _file(id);
    return file != null && await file.exists() ? file.path : null;
  }

  static Future<void> write(String id, Uint8List bytes) async {
    final file = await _file(id);
    if (file == null) return;
    // Written under another name first, so a half-written file is never taken for a saved picture.
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  static Future<void> delete(String id) async {
    final file = await _file(id);
    if (file != null && await file.exists()) await file.delete();
  }

  /// Memory ids that have a picture on this phone.
  static Future<Set<String>> ids() async {
    final root = await _root();
    if (root == null) return {};
    return {
      await for (final e in root.list())
        if (e is File && e.path.endsWith('.png')) e.uri.pathSegments.last.replaceAll('.png', ''),
    };
  }

  /// Removes every saved picture of the signed-in user (their account is being deleted).
  static Future<void> deleteAll() async {
    final root = await _root();
    if (root != null && await root.exists()) await root.delete(recursive: true);
  }
}
