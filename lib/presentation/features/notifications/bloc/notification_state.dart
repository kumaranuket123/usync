part of 'notification_bloc.dart';
sealed class NotifState {}
final class NotifLoading extends NotifState {}
final class NotifReady   extends NotifState {
  NotifReady(this.items);
  final List<NotificationItem> items;
  int get unreadCount => items.where((n) => !n.isRead).length;
}
final class NotifError   extends NotifState { NotifError(this.message); final String message; }
