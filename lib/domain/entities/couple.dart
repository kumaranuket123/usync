import 'package:equatable/equatable.dart';

/// Whether the couple lives apart or together; shared by both partners and
/// used to pick mode-specific content.
enum RelationshipMode {
  together('together', '🏡', 'Together', 'We live in the same place or see each other most days'),
  longDistance('long_distance', '✈️', 'Long-distance', 'We live apart and stay close through the app');

  const RelationshipMode(this.value, this.emoji, this.label, this.description);

  /// The value stored in `couples.relationship_mode`.
  final String value;
  final String emoji;
  final String label;
  final String description;

  static RelationshipMode fromString(String? value) =>
      RelationshipMode.values.firstWhere((m) => m.value == value, orElse: () => RelationshipMode.together);
}

class Couple extends Equatable {
  const Couple({
    required this.id,
    required this.userAId,
    required this.userBId,
    required this.pairedAt,
    this.streakDays    = 0,
    this.totalMoments  = 0,
    this.relationshipMode = RelationshipMode.together,
    this.nextMeetOn,
    this.disconnectRequestedBy,
    this.disconnectedAt,
  });

  final String   id;
  final String   userAId;
  final String   userBId;
  final DateTime pairedAt;
  final int      streakDays;
  final int      totalMoments;
  final RelationshipMode relationshipMode;
  /// The couple's next planned meeting, as a calendar date (time of day is unused); null when not set.
  final DateTime? nextMeetOn;
  /// uid of the partner who asked to disconnect; null when no request is pending.
  final String?  disconnectRequestedBy;
  final DateTime? disconnectedAt;

  bool get isDisconnected => disconnectedAt != null;

  int get daysTogether => DateTime.now().difference(pairedAt).inDays;

  String partnerIdFor(String userId) =>
      userId == userAId ? userBId : userAId;

  @override
  List<Object?> get props => [id, userAId, userBId, pairedAt, streakDays, totalMoments, relationshipMode, nextMeetOn, disconnectRequestedBy, disconnectedAt];
}
