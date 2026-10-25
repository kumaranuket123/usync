import '../../domain/entities/mood.dart';

class MoodModel extends Mood {
  const MoodModel({
    required super.type,
    required super.userId,
    required super.sentAt,
  });

  /// Row from the Supabase `moods` table.
  factory MoodModel.fromRow(Map<String, dynamic> row) => MoodModel(
    type:   MoodType.fromString(row['type'] as String),
    userId: row['user_id'] as String,
    sentAt: DateTime.parse(row['sent_at'] as String),
  );

  Map<String, dynamic> toRow(String coupleId) => {
    'couple_id': coupleId,
    'user_id':   userId,
    'type':      type.name,
    'sent_at':   sentAt.toUtc().toIso8601String(),
  };

  factory MoodModel.fromEntity(Mood mood) => MoodModel(
    type:   mood.type,
    userId: mood.userId,
    sentAt: mood.sentAt,
  );
}
