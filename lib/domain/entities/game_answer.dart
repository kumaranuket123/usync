import 'package:equatable/equatable.dart';

/// One player's answer for one round of an answer-based game.
class GameAnswer extends Equatable {
  const GameAnswer({required this.round, required this.userId, required this.content});

  final int    round;
  final String userId;
  /// What was answered; null when this phone cannot open it yet (no couple key).
  final Map<String, dynamic>? content;

  /// The pick of a would-you-rather round: `A` or `B`.
  String? get pick => content?['pick'] as String?;

  @override
  List<Object?> get props => [round, userId, content];
}
