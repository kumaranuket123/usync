import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/mood.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_mood_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../models/mood_model.dart';

class MoodRepository implements IMoodRepository {
  MoodRepository({required this.client, required this.notifications});

  final SupabaseClient          client;
  final INotificationRepository notifications;

  @override
  Future<void> sendMood(String coupleId, String userId, MoodType type, {CustomMood? custom}) async {
    final mood = MoodModel(
      type:        type,
      userId:      userId,
      sentAt:      DateTime.now(),
      customLabel: custom?.label,
      customEmoji: custom?.emoji,
    );
    // The row is both history and the "current" mood the partner's stream sees.
    await client.from('moods').insert(mood.toRow(coupleId));
    await notifications.notifyPartner(
      coupleId:   coupleId,
      fromUserId: userId,
      type:       NotifType.moodChange,
      body:       (name) => '$name is feeling ${mood.label} ${mood.emoji}',
    );
  }

  @override
  Stream<Mood?> watchPartnerMood(String coupleId, String partnerUserId) {
    return client
        .from('moods')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('sent_at', ascending: false)
        .limit(20)
        .map((rows) {
          for (final row in rows) {
            if (row['user_id'] == partnerUserId) return MoodModel.fromRow(row);
          }
          return null;
        })
        .handleError((Object _) {}); // dropped Realtime connection: keep the screen alive
  }

  @override
  Future<List<Mood>> getMoodHistory(String coupleId, {int limit = 10}) async {
    final rows = await client
        .from('moods')
        .select()
        .eq('couple_id', coupleId)
        .order('sent_at', ascending: false)
        .limit(limit);
    return rows.map(MoodModel.fromRow).toList();
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
