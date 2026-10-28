import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/crypto/content_cipher.dart';
import '../../core/services/outbox_service.dart';
import '../../domain/entities/memory.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_memory_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/local/local_memory_images.dart';
import '../datasources/local/prefs_source.dart';
import '../datasources/remote/storage_source.dart';
import '../models/memory_model.dart';

class MemoryRepository implements IMemoryRepository {
  MemoryRepository({
    required this.client,
    required this.storage,
    required this.notifications,
    required this.outbox,
    required this.prefs,
    required this.cipher,
  }) {
    outbox.register(_doodleType, _deliverDoodle);
  }

  static const _doodleType = 'doodle';

  /// The newest memories loaded at once; an unbounded list gets slower and
  /// costlier with every memory a couple adds.
  static const _pageSize = 100;

  /// Pictures beyond the newest this many are moved onto the couple's phones.
  static const keepOnServer = 10;

  final SupabaseClient          client;
  final StorageSource           storage;
  final INotificationRepository notifications;
  final OutboxService           outbox;
  final PrefsSource             prefs;
  final ContentCipher           cipher;
  final _uuid = const Uuid();

  /// The memory id is chosen here, not when sending, so retrying after a lost connection overwrites the
  /// same file and cannot add a second memory. The picture's path is derived from it.
  @override
  Future<bool> saveDoodle({
    required String    coupleId,
    required String    userId,
    required Uint8List png,
    required String    title,
  }) =>
      outbox.submit(_doodleType, {
        'id':        _uuid.v4(),
        'coupleId':  coupleId,
        'userId':    userId,
        'title':     title,
        'png':       png,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });

  /// Where a sealed picture lives in Storage.
  static String sealedPath(String coupleId, String memoryId) => '$coupleId/$memoryId.enc';

  /// What the readable columns hold for a sealed memory (the real text is only in `enc`).
  static const _placeholder = '🔒';

  Future<void> _deliverDoodle(Map<String, dynamic> p) async {
    final coupleId = p['coupleId'] as String;
    final userId   = p['userId'] as String;
    final id       = p['id'] as String;
    final emoji    = MemoryType.canvas.defaultEmoji;
    // Everything is sealed before it leaves the phone; without the couple key this throws and nothing is sent.
    final sealedText = await cipher.sealJson(
      {'title': p['title'], 'emoji': emoji},
      coupleId: coupleId, table: 'memories', rowId: id,
    );
    final sealedImage = await cipher.sealBytes(
      (p['png'] as List).cast<int>(),
      coupleId: coupleId, table: 'memories', rowId: id, field: 'image',
    );
    final path = sealedPath(coupleId, id);
    await storage.uploadSealedAt(path, sealedImage);
    try {
      await client.from('memories').insert({
        'id':                 id,
        'couple_id':          coupleId,
        'type':               MemoryType.canvas.name,
        'thumbnail_emoji':    _placeholder,
        'title':              _placeholder,
        'created_by_user_id': userId,
        'thumbnail_url':      path,
        'created_at':         p['createdAt'],
        'enc':                sealedText,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // an earlier attempt already got through
      rethrow;
    }
    await notifications.notifyPartner(
      coupleId:   coupleId,
      fromUserId: userId,
      type:       NotifType.doodle,
      body:       (name) => '$name saved a new doodle ✏️',
    );
  }

  /// Ids deleted on this phone. Realtime does not send deletes to a filtered
  /// subscription (only the primary key comes with them, so the couple filter
  /// cannot match), so the list would keep showing a memory removed from its
  /// detail screen. Hearing about our own deletes fixes that.
  final _deleted = StreamController<String>.broadcast();

  @override
  Stream<List<Memory>> watchMemories(String coupleId) {
    late final StreamController<List<Memory>> out;
    StreamSubscription<List<Memory>>? live;
    StreamSubscription<String>? local;
    var latest = <Memory>[];

    out = StreamController<List<Memory>>(
      onListen: () {
        live = client
            .from('memories')
            .stream(primaryKey: ['id'])
            .eq('couple_id', coupleId)
            .order('created_at', ascending: false)
            .limit(_pageSize)
            .asyncMap(_toMemories)
            .listen((list) {
          latest = list;
          out.add(list);
        }, onError: (Object _) {}); // dropped Realtime connection: keep the screen alive
        local = _deleted.stream.listen((id) {
          if (latest.any((m) => m.id == id)) {
            latest = [for (final m in latest) if (m.id != id) m];
            out.add(latest);
          }
        });
      },
      onCancel: () async {
        await live?.cancel();
        await local?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<List<Memory>> getMemories(String coupleId) async {
    final rows = await client
        .from('memories')
        .select()
        .eq('couple_id', coupleId)
        .order('created_at', ascending: false)
        .limit(_pageSize);
    return _toMemories(rows);
  }

  /// A memory from its row: sealed ones are opened, older readable ones are used as they are. One this phone
  /// cannot open (no key yet) shows as locked instead of disappearing. A picture saved on this phone (older
  /// memories, or archived ones) is shown from there; otherwise `thumbnailUrl` is the Storage path, loaded
  /// through [loadImage].
  Future<Memory> _toMemory(Map<String, dynamic> row, Map<String, String> local) async {
    var fields = row;
    final sealed = row['enc'] as String?;
    if (ContentCipher.isEncrypted(sealed)) {
      try {
        final c = await cipher.openJson(sealed!, coupleId: row['couple_id'] as String, table: 'memories', rowId: row['id'] as String);
        fields = {...row, 'title': c['title'], 'thumbnail_emoji': c['emoji']};
      } catch (e) {
        debugPrint('Could not read a memory: ${e.runtimeType}');
        fields = {...row, 'title': 'Locked until your key arrives', 'thumbnail_emoji': _placeholder};
      }
    }
    return MemoryModel.fromRow({...fields, 'thumbnail_url': local[row['id']] ?? row['thumbnail_url']});
  }

  Future<List<Memory>> _toMemories(List<Map<String, dynamic>> rows) async {
    final local = <String, String>{};
    try {
      for (final id in await LocalMemoryImages.ids()) {
        final path = await LocalMemoryImages.pathIfExists(id);
        if (path != null) local[id] = path;
      }
    } catch (_) {}
    return [for (final row in rows) await _toMemory(row, local)];
  }

  /// Newest pictures kept decoded in memory so lists and the detail screen do not fetch them again.
  static const _imageCacheSize = 24;
  final _images = <String, Uint8List>{};
  final _loading = <String, Future<Uint8List?>>{};

  @override
  Future<Uint8List?> loadImage(Memory memory) {
    final path = memory.thumbnailUrl;
    if (path == null || path.isEmpty) return Future.value(null);
    final cached = _images.remove(memory.id);
    if (cached != null) {
      _images[memory.id] = cached; // most recently used goes last
      return Future.value(cached);
    }
    return _loading[memory.id] ??= _fetchImage(memory.id, memory.coupleId, path).whenComplete(() {
      _loading.remove(memory.id); // not returned: a future must not wait for itself
    });
  }

  Future<Uint8List?> _fetchImage(String id, String coupleId, String path) async {
    try {
      final bytes = await _imageBytes(id, coupleId, path);
      _images[id] = bytes;
      if (_images.length > _imageCacheSize) _images.remove(_images.keys.first);
      return bytes;
    } catch (e) {
      debugPrint('Could not load a memory picture: ${e.runtimeType}');
      return null; // the emoji is shown instead
    }
  }

  /// The picture's real bytes: a path on this phone is read as it is, a Storage path is downloaded and, when
  /// sealed (`.enc`), opened. Older pictures (`.png`) were stored readable.
  Future<Uint8List> _imageBytes(String id, String coupleId, String path) async {
    if (path.startsWith('/')) return File(path).readAsBytes();
    final bytes = await storage.download(path);
    if (!path.endsWith('.enc')) return bytes;
    return cipher.openBytes(bytes, coupleId: coupleId, table: 'memories', rowId: id, field: 'image');
  }

  bool _archiving = false;

  @override
  Future<int> archiveOlderImages(String coupleId) async {
    if (_archiving) return 0;
    _archiving = true;
    var saved = 0;
    try {
      final uid = client.auth.currentUser?.id;
      if (uid == null) return 0;

      final older = await client
          .from('memories')
          .select('id, thumbnail_url, archived_by')
          .eq('couple_id', coupleId)
          .or('thumbnail_url.not.is.null,image_archived.eq.true')
          .order('created_at', ascending: false)
          .range(keepOnServer, _pageSize - 1);

      for (final row in older) {
        final path = row['thumbnail_url'] as String?;
        if (path == null) continue; // already off the server
        final id = row['id'] as String;
        try {
          // 1. A copy on this phone first: nothing is deleted without one.
          if (await LocalMemoryImages.pathIfExists(id) == null) {
            await LocalMemoryImages.write(id, await _imageBytes(id, coupleId, path));
            saved++;
          }
          // 2. Tell the server; the picture is removed once both partners have a copy.
          final archivedBy = (row['archived_by'] as List?)?.cast<String>() ?? const <String>[];
          final both = archivedBy.contains(uid)
              ? archivedBy.length >= 2
              : (await client.rpc('archive_memory_image', params: {'p_memory': id})) == true;
          if (!both) continue;
          await storage.remove(path);
          await client.rpc('finish_memory_archive', params: {'p_memory': id});
        } catch (_) {
          // This one is tried again next time; the others carry on.
        }
      }

      await _dropOrphanedCopies(coupleId);
      if (prefs.galleryBackupEnabled) await backupArchivedToGallery();
    } catch (_) {
      // Best effort: pictures simply stay on the server until the next try.
    } finally {
      _archiving = false;
    }
    return saved;
  }

  bool _backingUp = false;

  @override
  Future<int> backupArchivedToGallery() async {
    if (_backingUp) return 0;
    _backingUp = true;
    var copied = 0;
    try {
      final saved = prefs.gallerySavedIds;
      for (final id in await LocalMemoryImages.ids()) {
        if (saved.contains(id)) continue;
        final path = await LocalMemoryImages.pathIfExists(id);
        if (path == null) continue;
        await Gal.putImage(path, album: 'Usync');
        saved.add(id);
        copied++;
        // Remembered one by one, so an interruption never makes the next run save it again.
        await prefs.setGallerySavedIds(saved);
      }
    } finally {
      _backingUp = false;
    }
    return copied;
  }

  /// Copies kept for memories that no longer exist (deleted by the partner).
  Future<void> _dropOrphanedCopies(String coupleId) async {
    final rows = await client.from('memories').select('id').eq('couple_id', coupleId).limit(_pageSize + 1);
    if (rows.length > _pageSize) return; // not the whole list: could not tell
    final existing = {for (final r in rows) r['id'] as String};
    for (final id in await LocalMemoryImages.ids()) {
      if (!existing.contains(id)) await LocalMemoryImages.delete(id);
    }
  }

  @override
  Future<void> toggleFavourite(String memoryId, String coupleId, {required bool isFavourited}) =>
      client.from('memories').update({'is_favourited': isFavourited}).eq('id', memoryId);

  @override
  Future<void> deleteMemory(String memoryId, String coupleId) async {
    final row = await client.from('memories').select('thumbnail_url').eq('id', memoryId).maybeSingle();
    await client.from('memories').delete().eq('id', memoryId);
    _deleted.add(memoryId);
    _images.remove(memoryId);
    await LocalMemoryImages.delete(memoryId);
    final path = row?['thumbnail_url'] as String?;
    if (path != null) {
      try { await storage.remove(path); } catch (_) {}
    }
  }
}
