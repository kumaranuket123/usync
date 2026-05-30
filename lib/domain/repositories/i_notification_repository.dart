import '../entities/notification_item.dart';

abstract interface class INotificationRepository {
  Future<List<NotificationItem>> getNotifications(String coupleId);
  Stream<List<NotificationItem>> watchNotifications(String coupleId);
  Future<void>  markRead(String coupleId, String notificationId);
  Future<void>  markAllRead(String coupleId);
  Stream<int>   watchUnreadCount(String coupleId);
  Future<void>  toggleFcm({required bool enabled, required String uid});
}
