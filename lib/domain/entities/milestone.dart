import 'package:equatable/equatable.dart';

enum MilestoneType {
  firstConnect,
  firstDoodle,
  streak7,
  streak30,
  streak100,
  moments100,
  custom,
  today; // synthetic — never stored in Firestore

  String get emoji => switch (this) {
    MilestoneType.firstConnect => '🎉',
    MilestoneType.firstDoodle  => '✏️',
    MilestoneType.streak7      => '🔥',
    MilestoneType.streak30     => '🌙',
    MilestoneType.streak100    => '💫',
    MilestoneType.moments100   => '💖',
    MilestoneType.custom       => '✨',
    MilestoneType.today        => '✨',
  };

  String get defaultTitle => switch (this) {
    MilestoneType.firstConnect => 'You connected!',
    MilestoneType.firstDoodle  => 'First doodle together',
    MilestoneType.streak7      => '7-day streak achieved',
    MilestoneType.streak30     => '30-day streak',
    MilestoneType.streak100    => '100-day streak',
    MilestoneType.moments100   => '100 shared moments',
    MilestoneType.custom       => 'Special moment',
    MilestoneType.today        => 'Today',
  };

  static MilestoneType fromString(String value) =>
      MilestoneType.values.firstWhere((e) => e.name == value, orElse: () => MilestoneType.custom);
}

class Milestone extends Equatable {
  const Milestone({
    required this.id,
    required this.coupleId,
    required this.type,
    required this.title,
    required this.occurredAt,
    this.note,
    this.linkedMemoryId,
  });

  final String        id;
  final String        coupleId;
  final MilestoneType type;
  final String        title;
  final DateTime      occurredAt;
  final String?       note;
  final String?       linkedMemoryId;

  bool get hasLinkedMemory => linkedMemoryId != null;

  @override
  List<Object?> get props => [id, type, occurredAt];
}
