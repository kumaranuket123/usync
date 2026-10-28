import '../../domain/entities/notification_item.dart';

class NotificationModel extends NotificationItem {
  const NotificationModel({
    required super.id,
    required super.coupleId,
    required super.type,
    required super.bodyText,
    required super.timestamp,
    super.isRead,
    super.fromUserId,
  });

  /// Row from the Supabase `notifications` table. [detail] is the decrypted detail, shown in place of
  /// the fixed sentence the push carried.
  factory NotificationModel.fromRow(Map<String, dynamic> row, {String? detail}) => NotificationModel(
    id:         row['id']           as String,
    coupleId:   row['couple_id']    as String,
    type:       NotifType.fromString(row['type'] as String),
    bodyText:   detail ?? row['body_text'] as String,
    timestamp:  DateTime.parse(row['created_at'] as String),
    isRead:     row['is_read']      as bool? ?? false,
    fromUserId: row['from_user_id'] as String?,
  );
}
