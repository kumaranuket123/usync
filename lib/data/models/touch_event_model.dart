import '../../domain/entities/touch_event.dart';

class TouchEventModel extends TouchEvent {
  const TouchEventModel({
    required super.coupleId,
    required super.userId,
    required super.isActive,
    required super.timestamp,
  });

  factory TouchEventModel.fromJson(Map<String, dynamic> json) => TouchEventModel(
    coupleId:  json['coupleId']  as String,
    userId:    json['userId']    as String,
    isActive:  json['isActive']  as bool,
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
  );

  Map<String, dynamic> toJson() => {
    'coupleId':  coupleId,
    'userId':    userId,
    'isActive':  isActive,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };
}
