import '../../domain/entities/notification_item.dart';

class NotificationModel extends NotificationItem {
  const NotificationModel({
    required super.id,
    required super.coupleId,
    required super.type,
    required super.bodyText,
    required super.timestamp,
    super.isRead,
  });

  factory NotificationModel.fromJson(String id, Map<String, dynamic> json) => NotificationModel(
    id:        id,
    coupleId:  json['coupleId']  as String,
    type:      NotifType.fromString(json['type'] as String),
    bodyText:  json['bodyText']  as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    isRead:    json['isRead']    as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'coupleId':  coupleId,
    'type':      type.name,
    'bodyText':  bodyText,
    'timestamp': timestamp.toIso8601String(),
    'isRead':    isRead,
  };
}
