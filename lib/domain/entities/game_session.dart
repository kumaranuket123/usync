import 'package:equatable/equatable.dart';

enum GameType {
  ticTacToe('tic_tac_toe', 'Tic-Tac-Toe', '⭕'),
  quiz('quiz', 'How well do you know me?', '🧠'),
  wouldYouRather('would_you_rather', 'Would you rather', '🤔'),
  cards('cards', 'Conversation cards', '🃏');

  const GameType(this.key, this.title, this.emoji);

  /// The value stored in `game_sessions.game_type`.
  final String key;
  final String title;
  final String emoji;

  /// Whether the game is played in turns; the others have each partner answer at their own pace.
  bool get isTurnBased => this == ticTacToe;

  static GameType? fromKey(String key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// One running or finished game between the two partners.
class GameSession extends Equatable {
  const GameSession({
    required this.id,
    required this.coupleId,
    required this.type,
    required this.isActive,
    required this.state,
    required this.version,
    required this.updatedAt,
    this.turnUserId,
    this.createdBy,
  });

  final String               id;
  final String               coupleId;
  final GameType             type;
  final bool                 isActive;
  /// Public state of the game; its shape depends on [type].
  final Map<String, dynamic> state;
  /// Bumped on every change; a move must name the version it was made on.
  final int                  version;
  final DateTime             updatedAt;
  /// Whose turn it is; null once the game is over.
  final String?              turnUserId;
  final String?              createdBy;

  bool isMyTurn(String userId) => isActive && turnUserId == userId;

  @override
  List<Object?> get props => [id, isActive, version, turnUserId];
}
