import 'package:equatable/equatable.dart';

enum MoodType {
  happy,
  thinkingAboutYou,
  missingYou,
  sleeping,
  relaxing,
    busy,
  /// Typed by the user; the text and emoji travel with the mood.
  custom;

  String get label => switch (this) {
    MoodType.happy            => 'Happy',
    MoodType.thinkingAboutYou => 'Thinking About You',
    MoodType.missingYou       => 'Missing You',
    MoodType.sleeping         => 'Sleeping',
    MoodType.relaxing         => 'Relaxing',
    MoodType.busy             => 'Busy',
    MoodType.custom           => 'Custom',
  };

  String get emoji => switch (this) {
    MoodType.happy            => '😊',
    MoodType.thinkingAboutYou => '💭',
    MoodType.missingYou       => '💖',
    MoodType.sleeping         => '😴',
    MoodType.relaxing         => '🌸',
    MoodType.busy             => '⚡',
    MoodType.custom           => '✨',
  };

  static MoodType fromString(String value) =>
      MoodType.values.firstWhere((e) => e.name == value, orElse: () => MoodType.happy);
}

class Mood extends Equatable {
  const Mood({
    required this.type,
    required this.userId,
    required this.sentAt,
    this.customLabel,
    this.customEmoji,
  });

  final MoodType type;
  final String   userId;
  final DateTime sentAt;
  /// Only set when [type] is [MoodType.custom].
  final String?  customLabel;
  final String?  customEmoji;

  String get label => type == MoodType.custom ? (customLabel ?? type.label) : type.label;
  String get emoji => type == MoodType.custom ? (customEmoji ?? type.emoji) : type.emoji;

  @override
  List<Object?> get props => [type, userId, sentAt, customLabel, customEmoji];
}

/// A mood a user made up, offered again the next time they pick a mood.
class CustomMood extends Equatable {
  const CustomMood({required this.label, required this.emoji});
  final String label;
  final String emoji;

  @override
  List<Object?> get props => [label, emoji];
}
