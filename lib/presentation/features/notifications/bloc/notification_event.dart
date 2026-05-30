part of 'notification_bloc.dart';
sealed class NotificationEvent { const NotificationEvent(); }
final class NotificationsLoaded  extends NotificationEvent { NotificationsLoaded(this.coupleId); final String coupleId; }
final class NotificationsUpdated extends NotificationEvent { NotificationsUpdated(this.items); final List<NotificationItem> items; }
final class NotificationRead     extends NotificationEvent { NotificationRead({required this.id, required this.coupleId}); final String id, coupleId; }
final class AllNotificationsRead extends NotificationEvent { AllNotificationsRead(this.coupleId); final String coupleId; }
