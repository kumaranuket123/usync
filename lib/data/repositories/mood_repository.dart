import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/outbox_service.dart';
import '../../domain/entities/mood.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_mood_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/local/session_cache.dart';
import '../models/mood_model.dart';

class MoodRepository implements IMoodRepository {
  MoodRepository({
    required this.client,
    required this.notifications,
    required this.outbox,
    required this.sessionCache,
  }) {
    outbox.register(_outboxType, _deliver);
  }

  static const _outboxType = 'mood';

  final SupabaseClient          client;
  final INotificationRepository notifications;
  final OutboxService           outbox;
  final SessionCache            sessionCache;
  final _uuid = const Uuid();

  /// Sends now when there is a connection; otherwise the mood waits on the
  /// device (with the time it was made) and goes out when the connection is
  /// back. The id is chosen here so a retry can never create a second mood.
  @override
  Future<bool> sendMood(String coupleId, String userId, MoodType type, {CustomMood? custom}) =>
      outbox.submit(_outboxType, {
        'id':          _uuid.v4(),
        'coupleId':    coupleId,
        'userId':      userId,
        'type':        type.name,
        'customLabel': custom?.label,
        'customEmoji': custom?.emoji,
        'sentAt':      DateTime.now().toUtc().toIso8601String(),
      });

  Future<void> _deliver(Map<String, dynamic> p) async {
    final type = MoodType.fromString(p['type'] as String);
    final mood = MoodModel(
      type:        type,
      userId:      p['userId'] as String,
      sentAt:      DateTime.parse(p['sentAt'] as String),
      customLabel: p['customLabel'] as String?,
      customEmoji: p['customEmoji'] as String?,
    );
    try {
      await client.from('moods').insert({'id': p['id'], ...mood.toRow(p['coupleId'] as String)});
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // an earlier attempt already got through
      rethrow;
    }
    await notifications.notifyPartner(
      coupleId:   p['coupleId'] as String,
      fromUserId: p['userId'] as String,
      type:       NotifType.moodChange,
      body:       (name) => '$name is feeling ${mood.label} ${mood.emoji}',
    );
  }

  static const _recentLimit = 20;

  @override
  Stream<List<Mood>> watchRecentMoods(String coupleId) async* {
    final key = SessionCache.moods(coupleId);
    // The last list we saw, so Home has something to show at once (and offline).
    final cached = sessionCache.getList(key);
    if (cached != null) yield cached.map(MoodModel.fromRow).toList();

    yield* client
        .from('moods')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('sent_at', ascending: false)
        .limit(_recentLimit)
        .map((rows) {
          sessionCache.put(key, rows).ignore();
          return rows.map(MoodModel.fromRow).toList();
        })
        .handleError((Object _) {}); // dropped Realtime connection: keep the screen alive
  }

  @override
  Future<Mood?> getLastSentMood(String userId) async {
    final row = await client
        .from('moods')
        .select()
        .eq('user_id', userId)
        .order('sent_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : MoodModel.fromRow(row);
  }

  /// The most moods one query returns: far more than a couple shares in a week.
  static const _sinceLimit = 500;

  @override
  Future<List<Mood>> getMoodsSince(String coupleId, DateTime since) async {
    final rows = await client
        .from('moods')
        .select()
        .eq('couple_id', coupleId)
        .gte('sent_at', since.toUtc().toIso8601String())
        .order('sent_at', ascending: true)
        .limit(_sinceLimit);
    return rows.map(MoodModel.fromRow).toList();
  }

  @override
  Future<List<CustomMood>> getMyCustomMoods(String userId, {int limit = 6}) async {
    final rows = await client
        .from('moods')
        .select('custom_label, custom_emoji')
        .eq('user_id', userId)
        .eq('type', 'custom')
        .order('sent_at', ascending: false)
        .limit(40);
    final seen = <CustomMood>{};
    for (final row in rows) {
      final label = row['custom_label'] as String?;
      if (label == null || label.isEmpty) continue;
      seen.add(CustomMood(label: label, emoji: (row['custom_emoji'] as String?) ?? MoodType.custom.emoji));
      if (seen.length == limit) break;
    }
    return seen.toList();
  }
}
