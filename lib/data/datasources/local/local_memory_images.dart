import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/device_key.dart';

/// Pictures of older memories, kept on the phone after they are removed from the
/// server (see `MemoryRepository.archiveOlderImages`). One file per memory id in
/// the app's own `usync/memories` folder.
///
/// The files are encrypted with the phone's local key ([DeviceKey]), so another app, a file browser or a
/// backup of the app's folder only sees ciphertext. Nothing opens a file directly: [read] gives the
/// picture's bytes and [withPlainCopy] hands a short-lived readable copy to something that needs a file
/// (the gallery, the share sheet). Pictures saved by earlier versions were plain PNGs; [sealLegacy] seals them.
///
/// Kept per signed-in user (`usync/memories/<user id>/`): the next person to
/// sign in on this phone never sees them or touches them, and they are still
/// here when their owner signs back in.
abstract final class LocalMemoryImages {
  static DeviceKey? _key;

  /// Called once at start-up. Without it nothing can be written (never a readable file instead).
  static void configure(DeviceKey key) => _key = key;

  @visibleForTesting
  static void unconfigure() => _key = null;

  /// Where the signed-in user's pictures live; replaced in tests.
  @visibleForTesting
  static Future<Directory?> Function() rootProvider = _defaultRoot;

  static Future<Directory?> _defaultRoot() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/usync/memories/$uid').create(recursive: true);
  }

  static Future<File?> _file(String id) async {
    final root = await rootProvider();
    return root == null ? null : File('${root.path}/$id.png');
  }

  /// A PNG's first bytes: what a picture saved by an earlier (unencrypted) version starts with.
  static const _pngMagic = [0x89, 0x50, 0x4E, 0x47];

  static bool _isPlainPng(Uint8List bytes) =>
      bytes.length >= _pngMagic.length && [for (var i = 0; i < _pngMagic.length; i++) bytes[i] == _pngMagic[i]].every((b) => b);

  /// The saved picture's path, or null when this phone has none. The file is encrypted: do not open it,
  /// use [read].
  static Future<String?> pathIfExists(String id) async {
    final file = await _file(id);
    return file != null && await file.exists() ? file.path : null;
  }

  /// The picture's bytes, or null when this phone has none (or it cannot be read).
  static Future<Uint8List?> read(String id) async {
    final file = await _file(id);
    final key = _key;
    if (file == null || key == null || !await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (_isPlainPng(bytes)) {
      await _sealInPlace(file, id, bytes); // an older picture: protected the first time it is used
      return bytes;
    }
    try {
      return await key.openFile(id, bytes);
    } catch (e) {
      debugPrint('Could not open a saved picture: ${e.runtimeType}');
      return null;
    }
  }

  static Future<void> write(String id, Uint8List bytes) async {
    final file = await _file(id);
    final key = _key;
    if (file == null) return;
    if (key == null) throw StateError('Local pictures cannot be saved before the local key is ready');
    await _writeAtomically(file, await key.sealFile(id, bytes));
  }

  static Future<void> _writeAtomically(File file, Uint8List bytes) async {
    // Written under another name first, so a half-written file is never taken for a saved picture.
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  static Future<void> _sealInPlace(File file, String id, Uint8List plain) async {
    try {
      await _writeAtomically(file, await _key!.sealFile(id, plain));
    } catch (_) {
      // Left as it is; sealed the next time.
    }
  }

  /// Seals every picture an earlier version left readable. Cheap when there is none.
  static Future<void> sealLegacy() async {
    final root = await rootProvider();
    if (root == null || _key == null) return;
    await for (final e in root.list()) {
      if (e is! File || !e.path.endsWith('.png')) continue;
      final id = e.uri.pathSegments.last.replaceAll('.png', '');
      final bytes = await e.readAsBytes();
      if (_isPlainPng(bytes)) await _sealInPlace(e, id, bytes);
    }
  }

  /// Gives [use] the picture as a readable file for as long as it runs, then deletes that copy. For the
  /// few things that need a real file (saving to the gallery, sharing).
  static Future<T?> withPlainCopy<T>(String id, Future<T> Function(String path) use) async {
    final bytes = await read(id);
    final root = await rootProvider();
    if (bytes == null || root == null) return null;
    final copy = File('${root.path}/$id.plain.tmp.png');
    await copy.writeAsBytes(bytes, flush: true);
    try {
      return await use(copy.path);
    } finally {
      if (await copy.exists()) await copy.delete();
    }
  }

  static Future<void> delete(String id) async {
    final file = await _file(id);
    if (file != null && await file.exists()) await file.delete();
  }

  /// Memory ids that have a picture on this phone.
  static Future<Set<String>> ids() async {
    final root = await rootProvider();
    if (root == null) return {};
    return {
      await for (final e in root.list())
        if (e is File && e.path.endsWith('.png') && !e.path.endsWith('.plain.tmp.png')) e.uri.pathSegments.last.replaceAll('.png', ''),
    };
  }

  /// Removes every saved picture of the signed-in user (their account is being deleted).
  static Future<void> deleteAll() async {
    final root = await rootProvider();
    if (root != null && await root.exists()) await root.delete(recursive: true);
  }
}
