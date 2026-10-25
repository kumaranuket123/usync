import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../models/notification_model.dart';

class NotificationRepository implements INotificationRepository {
  NotificationRepository({required this.client});
  final SupabaseClient client;

  @override
  Future<List<NotificationItem>> getNotifications(String coupleId) async {
    final rows = await client
        .from('notifications')
        .select()
        .eq('couple_id', coupleId)
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map(NotificationModel.fromRow).toList();
  }

  @override
  Stream<List<NotificationItem>> watchNotifications(String coupleId) {
    return client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('created_at', ascending: false)
        .limit(50)
        .map((rows) => rows.map(NotificationModel.fromRow).toList());
  }

  @override
  Future<void> markRead(String coupleId, String notificationId) =>
      client.from('notifications').update({'is_read': true}).eq('id', notificationId);

  @override
  Future<void> markAllRead(String coupleId) => client
      .from('notifications')
      .update({'is_read': true})
      .eq('couple_id', coupleId)
      .eq('is_read', false);

  @override
  Stream<int> watchUnreadCount(String coupleId) {
    return client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => rows.where((r) => r['is_read'] == false).length);
  }

  @override
  Future<void> notifyPartner({
    required String coupleId,
    required String fromUserId,
    required NotifType type,
    required String Function(String senderName) body,
  }) async {
    try {
      final me   = await client.from('profiles').select('username').eq('id', fromUserId).maybeSingle();
      final name = (me?['username'] as String?) ?? 'Your partner';
      // The recipient is the sender's partner; the push (phase 5) is sent by an Edge Function.
      await client.from('notifications').insert({
        'couple_id':    coupleId,
        'from_user_id': fromUserId,
        'type':         type.name,
        'body_text':    body(name),
      });
    } catch (_) {}
  }

  @override
  Future<void> toggleFcm({required bool enabled, required String uid}) async {
    if (enabled) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await client.from('device_tokens').upsert({
          'user_id':    uid,
          'fcm_token':  token,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } else {
      await FirebaseMessaging.instance.deleteToken();
      await client.from('device_tokens').delete().eq('user_id', uid);
    }
  }
}
