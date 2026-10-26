import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/outbox_service.dart';
import '../../domain/entities/memory.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_memory_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/remote/storage_source.dart';
import '../models/memory_model.dart';

class MemoryRepository implements IMemoryRepository {
  MemoryRepository({
    required this.client,
    required this.storage,
    required this.notifications,
    required this.outbox,
  }) {
    outbox.register(_doodleType, _deliverDoodle);
  }

  static const _doodleType = 'doodle';

  /// The newest memories loaded at once; an unbounded list gets slower and
  /// costlier with every memory a couple adds.
  static const _pageSize = 100;

  final SupabaseClient          client;
  final StorageSource           storage;
  final INotificationRepository notifications;
  final OutboxService           outbox;
  final _uuid = const Uuid();

  /// The file path and memory id are chosen here, not when sending, so retrying
  /// after a lost connection overwrites the same file and cannot add a second
  /// memory.
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
        'path':      '$coupleId/${_uuid.v4()}.png',
        'png':       png,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });

  Future<void> _deliverDoodle(Map<String, dynamic> p) async {
    final coupleId = p['coupleId'] as String;
    final userId   = p['userId'] as String;
    await storage.uploadPngAt(p['path'] as String, Uint8List.fromList((p['png'] as List).cast<int>()));
    try {
      await client.from('memories').insert({
        'id':                 p['id'],
        'couple_id':          coupleId,
        'type':               MemoryType.canvas.name,
        'thumbnail_emoji':    MemoryType.canvas.defaultEmoji,
        'title':              p['title'],
        'created_by_user_id': userId,
        'thumbnail_url':      p['path'],
        'created_at':         p['createdAt'],
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
            .asyncMap(_withSignedUrls)
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
    return _withSignedUrls(rows);
  }

  @override
  Future<Memory> saveMemory(Memory memory) async {
    final row = await client
        .from('memories')
        .insert(MemoryModel.fromEntity(memory).toRow())
        .select()
        .single();
    await notifications.notifyPartner(
      coupleId:   memory.coupleId,
      fromUserId: memory.createdByUserId,
      type:       memory.type == MemoryType.canvas ? NotifType.doodle : NotifType.milestone,
      body:       (name) => memory.type == MemoryType.canvas
          ? '$name saved a new doodle ✏️'
          : '$name added a new memory 💖',
    );
    return (await _withSignedUrls([row])).first;
  }

  /// `thumbnail_url` stores a private storage path; swap it for a signed URL the UI can load.
  Future<List<Memory>> _withSignedUrls(List<Map<String, dynamic>> rows) async {
    Map<String, String> urls = {};
    try {
      urls = await storage.signedUrls(rows.map((r) => (r['thumbnail_url'] as String?) ?? ''));
    } catch (_) {} // fall back to the emoji thumbnail
    return [
      for (final row in rows)
        MemoryModel.fromRow({
          ...row,
          'thumbnail_url': urls[row['thumbnail_url']] ?? row['thumbnail_url'],
        }),
    ];
  }

  @override
  Future<void> toggleFavourite(String memoryId, String coupleId, {required bool isFavourited}) =>
      client.from('memories').update({'is_favourited': isFavourited}).eq('id', memoryId);

  @override
  Future<void> deleteMemory(String memoryId, String coupleId) async {
    final row = await client.from('memories').select('thumbnail_url').eq('id', memoryId).maybeSingle();
    await client.from('memories').delete().eq('id', memoryId);
    _deleted.add(memoryId);
    final path = row?['thumbnail_url'] as String?;
    if (path != null) {
      try { await storage.remove(path); } catch (_) {}
    }
  }

  @override
  Future<String> uploadCanvasBitmap(String coupleId, Uint8List bytes) =>
      storage.uploadPng(coupleId, bytes);
}
