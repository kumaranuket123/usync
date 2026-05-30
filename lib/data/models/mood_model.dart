import '../../domain/entities/mood.dart';

class MoodModel extends Mood {
  const MoodModel({
    required super.type,
    required super.userId,
    required super.sentAt,
  });

  factory MoodModel.fromJson(Map<String, dynamic> json) => MoodModel(
    type:   MoodType.fromString(json['type'] as String),
    userId: json['userId'] as String,
    sentAt: DateTime.parse(json['sentAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'type':   type.name,
    'label':  label,
    'emoji':  emoji,
    'userId': userId,
    'sentAt': sentAt.toIso8601String(),
  };

  factory MoodModel.fromEntity(Mood mood) => MoodModel(
    type:   mood.type,
    userId: mood.userId,
    sentAt: mood.sentAt,
  );
}
