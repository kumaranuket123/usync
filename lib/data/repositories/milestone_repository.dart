import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/outbox_service.dart';
import '../../core/utils/network_errors.dart';
import '../../domain/entities/milestone.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_milestone_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/local/session_cache.dart';
import '../models/milestone_model.dart';

class MilestoneRepository implements IMilestoneRepository {
  MilestoneRepository({
    required this.client,
    required this.notifications,
    required this.outbox,
    required this.sessionCache,
  }) {
    outbox.register(_outboxType, _deliver);
  }

  static const _outboxType = 'milestone';

  final SupabaseClient          client;
  final INotificationRepository notifications;
  final OutboxService           outbox;
  final SessionCache            sessionCache;
  final _uuid = const Uuid();

  @override
  Future<List<Milestone>> getMilestones(String coupleId) async {
    final key = SessionCache.milestones(coupleId);
    try {
      final rows = await client
          .from('milestones')
          .select()
          .eq('couple_id', coupleId)
          .order('occurred_at');
      await sessionCache.put(key, rows);
      return <Milestone>[for (final row in rows) MilestoneModel.fromRow(row)];
    } catch (e) {
      final cached = isNetworkError(e) ? sessionCache.getList(key) : null;
      if (cached != null) return <Milestone>[for (final row in cached) MilestoneModel.fromRow(row)];
      rethrow;
    }
  }

  @override
  Future<({bool sentNow, Milestone milestone})> addDate({
    required String   coupleId,
    required String   userId,
    required String   title,
    required DateTime date,
    String?           note,
    required String   emoji,
    required bool     repeatsYearly,
  }) async {
    // Noon UTC keeps the calendar day the same in every timezone.
    final occurredAt = DateTime.utc(date.year, date.month, date.day, 12);
    final id = _uuid.v4();
    final sentNow = await outbox.submit(_outboxType, {
      'id':            id,
      'coupleId':      coupleId,
      'userId':        userId,
      'title':         title,
      'note':          note,
      'emoji':         emoji,
      'repeatsYearly': repeatsYearly,
      'occurredAt':    occurredAt.toIso8601String(),
    });
    return (
      sentNow: sentNow,
      milestone: Milestone(
        id:            id,
        coupleId:      coupleId,
        type:          MilestoneType.custom,
        title:         title,
        occurredAt:    occurredAt,
        note:          note,
        emoji:         emoji,
        repeatsYearly: repeatsYearly,
      ),
    );
  }

  Future<void> _deliver(Map<String, dynamic> p) async {
    try {
      await client.from('milestones').insert({
        'id':             p['id'],
        'couple_id':      p['coupleId'],
        'type':           MilestoneType.custom.name,
        'title':          p['title'],
        'note':           p['note'],
        'emoji':          p['emoji'],
        'repeats_yearly': p['repeatsYearly'],
        'occurred_at':    p['occurredAt'],
        'created_by':     p['userId'],
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // an earlier attempt already got through
      rethrow;
    }
    await notifications.notifyPartner(
      coupleId:   p['coupleId'] as String,
      fromUserId: p['userId'] as String,
      type:       NotifType.milestone,
      body:       (name) => '$name added a date to your timeline 🕰️',
      detail:     (name) => '$name added "${p['title']}" to your timeline ${p['emoji']}',
    );
  }

  @override
  Future<void> deleteMilestone(String id) => client.from('milestones').delete().eq('id', id);
}
