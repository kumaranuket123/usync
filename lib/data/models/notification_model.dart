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

  /// The map kept on this phone (see NotificationLocalSource).
  static Map<String, dynamic> toMap(NotificationItem n) => {
    'id':     n.id,
    'couple': n.coupleId,
    'type':   n.type.name,
    'body':   n.bodyText,
    'at':     n.timestamp.millisecondsSinceEpoch,
    'read':   n.isRead,
    'from':   n.fromUserId,
  };

  factory NotificationModel.fromMap(Map<String, dynamic> m) => NotificationModel(
    id:         m['id']     as String,
    coupleId:   m['couple'] as String,
    type:       NotifType.fromString(m['type'] as String),
    bodyText:   m['body']   as String,
    timestamp:  DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
    isRead:     m['read']   as bool? ?? false,
    fromUserId: m['from']   as String?,
  );
}
