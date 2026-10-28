import '../entities/notification_item.dart';

abstract interface class INotificationRepository {
  Future<List<NotificationItem>> getNotifications(String coupleId);
  Stream<List<NotificationItem>> watchNotifications(String coupleId);
  Future<void>  markRead(String coupleId, String notificationId);
  Future<void>  markAllRead(String coupleId);
  Stream<int>   watchUnreadCount(String coupleId);
  /// Records an event for the partner of [fromUserId]; a Cloud Function turns it into a push.
  /// Never throws: a failed notification must not break the action that triggered it.
  ///
  /// [body] is what the push and the stored row say, so it must be a FIXED sentence that never quotes
  /// anything a person typed. [detail] is the specific text (a mood name, a title, a date): it is
  /// encrypted for the partner and shown inside the app only. Without the couple key it is left out.
  Future<void>  notifyPartner({
    required String coupleId,
    required String fromUserId,
    required NotifType type,
    required String Function(String senderName) body,
    String Function(String senderName)? detail,
  });
  Future<void>  toggleFcm({required bool enabled, required String uid});
  /// Alert groups (see [NotifType.soundGroup]) that arrive without sound or popup.
  Future<Set<String>> getSilentTypes();
  Future<void>        setSilentTypes(Set<String> types);
}
