import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/crypto/content_cipher.dart';
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
    required this.cipher,
  }) {
    outbox.register(_outboxType, _deliver);
  }

  static const _outboxType = 'milestone';

  final SupabaseClient          client;
  final INotificationRepository notifications;
  final OutboxService           outbox;
  final SessionCache            sessionCache;
  final ContentCipher           cipher;
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
      await sessionCache.put(key, rows); // the saved copy stays sealed
      return _toMilestones(rows);
    } catch (e) {
      final cached = isNetworkError(e) ? sessionCache.getList(key) : null;
      if (cached != null) return _toMilestones(cached);
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

  /// What the readable columns hold for a sealed date (the real content is only in `enc`). The day is a fixed
  /// placeholder too, so the server cannot see when the date is.
  static const _placeholder   = '🔒';
  static final _placeholderAt = DateTime.utc(1970, 1, 1, 12).toIso8601String();

  Future<void> _deliver(Map<String, dynamic> p) async {
    // Sealed before it leaves the phone; without the couple key this throws and nothing is sent.
    final sealed = await cipher.sealJson(
      {
        'title':         p['title'],
        'note':          p['note'],
        'emoji':         p['emoji'],
        'repeatsYearly': p['repeatsYearly'],
        'occurredAt':    p['occurredAt'],
      },
      coupleId: p['coupleId'] as String, table: 'milestones', rowId: p['id'] as String,
    );
    try {
      await client.from('milestones').insert({
        'id':             p['id'],
        'couple_id':      p['coupleId'],
        'type':           MilestoneType.custom.name,
        'title':          _placeholder,
        'repeats_yearly': false,
        'occurred_at':    _placeholderAt,
        'created_by':     p['userId'],
        'enc':            sealed,
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

  /// A date from its row: sealed ones are opened, readable ones (older dates, and the milestones the server
  /// writes itself) are used as they are. One this phone cannot open (no key yet) shows as locked.
  Future<Milestone> _toMilestone(Map<String, dynamic> row) async {
    final sealed = row['enc'] as String?;
    if (!ContentCipher.isEncrypted(sealed)) return MilestoneModel.fromRow(row);
    try {
      final c = await cipher.openJson(sealed!, coupleId: row['couple_id'] as String, table: 'milestones', rowId: row['id'] as String);
      return MilestoneModel.fromRow({
        ...row,
        'title':          c['title'],
        'note':           c['note'],
        'emoji':          c['emoji'],
        'repeats_yearly': c['repeatsYearly'] == true,
        'occurred_at':    c['occurredAt'],
      });
    } catch (e) {
      debugPrint('Could not read a timeline date: ${e.runtimeType}');
      return MilestoneModel.fromRow({...row, 'title': 'Locked until your key arrives', 'note': null, 'emoji': _placeholder});
    }
  }

  Future<List<Milestone>> _toMilestones(List<Map<String, dynamic>> rows) async => [for (final row in rows) await _toMilestone(row)];

  @override
  Future<void> deleteMilestone(String id) => client.from('milestones').delete().eq('id', id);
}
