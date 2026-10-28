import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/crypto/content_cipher.dart';
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
    required this.cipher,
  }) {
    outbox.register(_outboxType, _deliver);
  }

  static const _outboxType = 'mood';

  final SupabaseClient          client;
  final INotificationRepository notifications;
  final OutboxService           outbox;
  final SessionCache            sessionCache;
  final ContentCipher           cipher;
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
    final id = p['id'] as String;
    final coupleId = p['coupleId'] as String;
    // Sealed before it leaves the phone (throws EncryptionNotReady without the couple key, and nothing is sent).
    final sealed = await cipher.sealJson(
      {'type': type.name, 'label': mood.customLabel, 'emoji': mood.customEmoji},
      coupleId: coupleId, table: 'moods', rowId: id,
    );
    try {
      await client.from('moods').insert({
        'id':        id,
        'couple_id': coupleId,
        'user_id':   mood.userId,
        'type':      MoodType.custom.name, // a placeholder: the real mood is only in `enc`
        'sent_at':   mood.sentAt.toUtc().toIso8601String(),
        'enc':       sealed,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // an earlier attempt already got through
      rethrow;
    }
    await notifications.notifyPartner(
      coupleId:   p['coupleId'] as String,
      fromUserId: p['userId'] as String,
      type:       NotifType.moodChange,
      body:       (name) => '$name shared a mood 💭',
      detail:     (name) => '$name is feeling ${mood.label} ${mood.emoji}',
    );
  }

  /// A mood from a row: sealed ones are opened, and older readable ones are used as they are.
  /// A sealed mood this phone cannot open (no key yet) is left out rather than shown wrong.
  Future<Mood?> _toMood(Map<String, dynamic> row) async {
    final sealed = row['enc'] as String?;
    if (!ContentCipher.isEncrypted(sealed)) return MoodModel.fromRow(row);
    try {
      final c = await cipher.openJson(sealed!, coupleId: row['couple_id'] as String, table: 'moods', rowId: row['id'] as String);
      return MoodModel(
        type:        MoodType.fromString(c['type'] as String),
        userId:      row['user_id'] as String,
        sentAt:      DateTime.parse(row['sent_at'] as String),
        customLabel: c['label'] as String?,
        customEmoji: c['emoji'] as String?,
      );
    } catch (e) {
      debugPrint('Could not read a mood: ${e.runtimeType}');
      return null;
    }
  }

  Future<List<Mood>> _toMoods(List<Map<String, dynamic>> rows) async => [
        for (final row in rows) ...[if (await _toMood(row) case final mood?) mood],
      ];

  static const _recentLimit = 20;

  @override
  Stream<List<Mood>> watchRecentMoods(String coupleId) async* {
    final key = SessionCache.moods(coupleId);
    // The last list we saw, so Home has something to show at once (and offline).
    final cached = sessionCache.getList(key);
    if (cached != null) yield await _toMoods(cached);

    yield* client
        .from('moods')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('sent_at', ascending: false)
        .limit(_recentLimit)
        .asyncMap((rows) {
          sessionCache.put(key, rows).ignore(); // the saved copy stays sealed
          return _toMoods(rows);
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
    return row == null ? null : await _toMood(row);
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
    return _toMoods(rows);
  }

  @override
  Future<List<CustomMood>> getMyCustomMoods(String userId, {int limit = 6}) async {
    // Every new mood is stored with the placeholder type `custom`, so open them to find the real custom ones.
    final rows = await client
        .from('moods')
        .select()
        .eq('user_id', userId)
        .eq('type', 'custom')
        .order('sent_at', ascending: false)
        .limit(40);
    final seen = <CustomMood>{};
    for (final mood in await _toMoods(rows)) {
      if (mood.type != MoodType.custom) continue;
      final label = mood.customLabel;
      if (label == null || label.isEmpty) continue;
      seen.add(CustomMood(label: label, emoji: mood.customEmoji ?? MoodType.custom.emoji));
      if (seen.length == limit) break;
    }
    return seen.toList();
  }
}
