import 'package:equatable/equatable.dart';

enum MoodType {
  happy,
  thinkingAboutYou,
  missingYou,
  sleeping,
  relaxing,
  busy;

  String get label => switch (this) {
    MoodType.happy            => 'Happy',
    MoodType.thinkingAboutYou => 'Thinking About You',
    MoodType.missingYou       => 'Missing You',
    MoodType.sleeping         => 'Sleeping',
    MoodType.relaxing         => 'Relaxing',
    MoodType.busy             => 'Busy',
  };

  String get emoji => switch (this) {
    MoodType.happy            => '😊',
    MoodType.thinkingAboutYou => '💭',
    MoodType.missingYou       => '💖',
    MoodType.sleeping         => '😴',
    MoodType.relaxing         => '🌸',
    MoodType.busy             => '⚡',
  };

  static MoodType fromString(String value) =>
      MoodType.values.firstWhere((e) => e.name == value, orElse: () => MoodType.happy);
}

class Mood extends Equatable {
  const Mood({
    required this.type,
    required this.userId,
    required this.sentAt,
  });

  final MoodType type;
  final String   userId;
  final DateTime sentAt;

  String get label => type.label;
  String get emoji => type.emoji;

  @override
  List<Object?> get props => [type, userId, sentAt];
}
