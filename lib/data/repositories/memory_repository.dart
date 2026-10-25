import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/memory.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_memory_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/remote/storage_source.dart';
import '../models/memory_model.dart';

class MemoryRepository implements IMemoryRepository {
  MemoryRepository({required this.client, required this.storage, required this.notifications});

  final SupabaseClient          client;
  final StorageSource           storage;
  final INotificationRepository notifications;

  @override
  Stream<List<Memory>> watchMemories(String coupleId) {
    return client
        .from('memories')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('created_at', ascending: false)
        .asyncMap(_withSignedUrls)
        .handleError((Object _) {}); // dropped Realtime connection: keep the screen alive
  }

  @override
  Future<List<Memory>> getMemories(String coupleId) async {
    final rows = await client
        .from('memories')
        .select()
        .eq('couple_id', coupleId)
        .order('created_at', ascending: false);
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
    final path = row?['thumbnail_url'] as String?;
    if (path != null) {
      try { await storage.remove(path); } catch (_) {}
    }
  }

  @override
  Future<String> uploadCanvasBitmap(String coupleId, Uint8List bytes) =>
      storage.uploadPng(coupleId, bytes);
}
