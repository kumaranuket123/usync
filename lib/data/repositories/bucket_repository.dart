import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/crypto/content_cipher.dart';
import '../../core/services/outbox_service.dart';
import '../../domain/entities/bucket_item.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_bucket_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/local/session_cache.dart';
import '../models/bucket_item_model.dart';

class BucketRepository implements IBucketRepository {
  BucketRepository({
    required this.client,
    required this.notifications,
    required this.outbox,
    required this.sessionCache,
    required this.cipher,
  }) {
    outbox.register(_outboxType, _deliver);
  }

  static const _outboxType = 'bucket_item';

  final SupabaseClient          client;
  final INotificationRepository notifications;
  final OutboxService           outbox;
  final SessionCache            sessionCache;
  final ContentCipher           cipher;
  final _uuid = const Uuid();

  @override
  Stream<List<BucketItem>> watchItems(String coupleId) async* {
    final key = SessionCache.bucket(coupleId);
    // The last list we saw, so the screen has something to show at once (and offline).
    final cached = sessionCache.getList(key);
    if (cached != null) yield await _toItems(cached);

    yield* client
        .from('bucket_items')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('created_at', ascending: false)
        .asyncMap((rows) {
          sessionCache.put(key, rows).ignore(); // the saved copy stays sealed
          return _toItems(rows);
        })
        .handleError((Object _) {}); // dropped Realtime connection: keep the screen alive
  }

  /// The id is chosen here so a retry can never create a second item.
  @override
  Future<({bool sentNow, BucketItem item})> addItem({
    required String coupleId,
    required String userId,
    required String title,
    required String emoji,
    String?         note,
  }) async {
    final id  = _uuid.v4();
    final now = DateTime.now().toUtc();
    final sentNow = await outbox.submit(_outboxType, {
      'id':       id,
      'coupleId': coupleId,
      'userId':   userId,
      'title':    title,
      'emoji':    emoji,
      'note':     note,
    });
    return (
      sentNow: sentNow,
      item: BucketItem(
        id: id, coupleId: coupleId, title: title, emoji: emoji,
        note: note, createdBy: userId, createdAt: now,
      ),
    );
  }

  Future<void> _deliver(Map<String, dynamic> p) async {
    // Sealed before it leaves the phone; the readable columns only hold a placeholder.
    final sealed = await cipher.sealJson(
      {'title': p['title'], 'emoji': p['emoji'], 'note': p['note']},
      coupleId: p['coupleId'] as String, table: 'bucket_items', rowId: p['id'] as String,
    );
    try {
      await client.from('bucket_items').insert({
        'id':         p['id'],
        'couple_id':  p['coupleId'],
        'title':      _placeholder,
        'emoji':      _placeholder,
        'created_by': p['userId'],
        'enc':        sealed,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // an earlier attempt already got through
      rethrow;
    }
    await notifications.notifyPartner(
      coupleId:   p['coupleId'] as String,
      fromUserId: p['userId'] as String,
      type:       NotifType.milestone,
      body:       (name) => '$name added something to your bucket list 🎯',
      detail:     (name) => '$name added "${p['title']}" to your bucket list ${p['emoji']}',
    );
  }

  @override
  Future<void> setDone({
    required String     coupleId,
    required String     userId,
    required BucketItem item,
    required bool       done,
  }) async {
    await client.rpc('set_bucket_item_done', params: {'p_item': item.id, 'p_done': done});
    if (!done) return; // un-ticking is not news for the partner
    await notifications.notifyPartner(
      coupleId:   coupleId,
      fromUserId: userId,
      type:       NotifType.milestone,
      body:       (name) => '$name checked something off your bucket list 🎉',
      detail:     (name) => '$name checked off "${item.title}" 🎉',
    );
  }

  /// What the readable columns hold for a sealed item (the real text is only in `enc`).
  static const _placeholder = '🔒';

  /// An item from a row: sealed ones are opened, older readable ones are used as they are. One this
  /// phone cannot open (no key yet) shows as locked instead of disappearing.
  Future<BucketItem> _toItem(Map<String, dynamic> row) async {
    final sealed = row['enc'] as String?;
    if (!ContentCipher.isEncrypted(sealed)) return BucketItemModel.fromRow(row);
    try {
      final c = await cipher.openJson(sealed!, coupleId: row['couple_id'] as String, table: 'bucket_items', rowId: row['id'] as String);
      return BucketItemModel.fromRow({...row, 'title': c['title'], 'emoji': c['emoji'], 'note': c['note']});
    } catch (e) {
      debugPrint('Could not read a bucket-list item: ${e.runtimeType}');
      return BucketItemModel.fromRow({...row, 'title': 'Locked until your key arrives', 'emoji': _placeholder, 'note': null});
    }
  }

  Future<List<BucketItem>> _toItems(List<Map<String, dynamic>> rows) async => [for (final row in rows) await _toItem(row)];

  @override
  Future<void> deleteItem(String id) => client.from('bucket_items').delete().eq('id', id);
}
