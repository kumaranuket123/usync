import '../entities/notification_item.dart';

abstract interface class INotificationRepository {
  Future<List<NotificationItem>> getNotifications(String coupleId);
  Stream<List<NotificationItem>> watchNotifications(String coupleId);
  Future<void>  markRead(String coupleId, String notificationId);
  Future<void>  markAllRead(String coupleId);
  Stream<int>   watchUnreadCount(String coupleId);
  /// Records an event for the partner of [fromUserId]; a Cloud Function turns it into a push.
  /// Never throws: a failed notification must not break the action that triggered it.
  Future<void>  notifyPartner({
    required String coupleId,
    required String fromUserId,
    required NotifType type,
    required String Function(String senderName) body,
  });
  Future<void>  toggleFcm({required bool enabled, required String uid});
}
