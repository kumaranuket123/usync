import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../models/notification_model.dart';

class NotificationRepository implements INotificationRepository {
  NotificationRepository({required this.client});
  final SupabaseClient client;

  final _senderNames = <String, String>{};

  /// The sender's display name. The signed-in user's own name is already in
  /// their session (it was given at sign-up), so the common case costs no
  /// request; anyone else is looked up once and remembered.
  Future<String> _senderName(String uid) async {
    final user = client.auth.currentUser;
    if (user != null && user.id == uid) {
      final name = user.userMetadata?['username'];
      if (name is String && name.isNotEmpty) return name;
    }
    final known = _senderNames[uid];
    if (known != null) return known;
    final row  = await client.from('profiles').select('username').eq('id', uid).maybeSingle();
    final name = row?['username'] as String?;
    if (name == null) return 'Your partner';
    return _senderNames[uid] = name;
  }

  /// Notifications are stored couple-wide; the ones we sent are for the partner.
  String? get _me => client.auth.currentUser?.id;

  /// Touch and location alerts repeat every time someone taps or looks, which
  /// floods the list with identical lines. Show only the newest one per sender
  /// and kind; other types (doodles, moods, milestones) are distinct events.
  /// Returns the rows newest first.
  static List<Map<String, dynamic>> _collapseRepeats(List<Map<String, dynamic>> rows) {
    const repeating = {'touch': 'touch', 'location': 'location', 'locate': 'location'};
    final seen = <String>{};
    final newestFirst = [...rows]
      ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
    return [
      for (final row in newestFirst)
        if (!repeating.containsKey(row['type']) ||
            seen.add('${row['from_user_id']}:${repeating[row['type']]}'))
          row,
    ];
  }

  @override
  Future<List<NotificationItem>> getNotifications(String coupleId) async {
    final rows = await client
        .from('notifications')
        .select()
        .eq('couple_id', coupleId)
        .neq('from_user_id', _me ?? '')
        .order('created_at', ascending: false)
        .limit(50);
    return _collapseRepeats(rows).map(NotificationModel.fromRow).toList();
  }

  @override
  Stream<List<NotificationItem>> watchNotifications(String coupleId) {
    return client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('created_at', ascending: false)
        .limit(50)
        .map((rows) => _collapseRepeats(rows.where((r) => r['from_user_id'] != _me).toList())
            .map(NotificationModel.fromRow)
            .toList())
        .handleError((Object _) {}); // dropped Realtime connection: keep the screen alive
  }

  @override
  Future<void> markRead(String coupleId, String notificationId) =>
      client.from('notifications').update({'is_read': true}).eq('id', notificationId);

  @override
  Future<void> markAllRead(String coupleId) => client
      .from('notifications')
      .update({'is_read': true})
      .eq('couple_id', coupleId)
      .neq('from_user_id', _me ?? '')
      .eq('is_read', false);

  @override
  Stream<int> watchUnreadCount(String coupleId) {
    return client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => _collapseRepeats(rows.where((r) => r['from_user_id'] != _me).toList())
            .where((r) => r['is_read'] == false)
            .length)
        .handleError((Object _) {});
  }

  @override
  Future<void> notifyPartner({
    required String coupleId,
    required String fromUserId,
    required NotifType type,
    required String Function(String senderName) body,
  }) async {
    try {
      final name = await _senderName(fromUserId);
      // The recipient is the sender's partner; the push (phase 5) is sent by an Edge Function.
      await client.from('notifications').insert({
        'couple_id':    coupleId,
        'from_user_id': fromUserId,
        'type':         type.name,
        'body_text':    body(name),
      });
    } catch (_) {}
  }

  /// Turns pushes on or off for THIS device only; the account's other devices
  /// are not affected.
  @override
  Future<void> toggleFcm({required bool enabled, required String uid}) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (enabled) {
      if (token != null) await client.rpc('register_device_token', params: {'p_token': token});
    } else {
      // Remove the server row first (it needs the token), then the token itself.
      if (token != null) await client.from('device_tokens').delete().eq('fcm_token', token);
      await FirebaseMessaging.instance.deleteToken();
    }
  }

  /// Which alerts arrive quietly: one choice per person, kept on their profile
  /// so every device of theirs follows it.
  @override
  Future<Set<String>> getSilentTypes() async {
    final uid = _me;
    if (uid == null) return NotifType.defaultSilent;
    final row = await client.from('profiles').select('silent_types').eq('id', uid).maybeSingle();
    final types = row?['silent_types'];
    return types is List ? types.cast<String>().toSet() : NotifType.defaultSilent;
  }

  @override
  Future<void> setSilentTypes(Set<String> types) async {
    final uid = _me;
    if (uid == null) return;
    await client.from('profiles').update({'silent_types': types.toList()}).eq('id', uid);
  }
}
