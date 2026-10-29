import '../entities/game_answer.dart';
import '../entities/game_session.dart';

abstract interface class IGameRepository {
  /// Every game of the couple, newest activity first; updates live.
  Stream<List<GameSession>> watchSessions(String coupleId);

  /// Starts a game of [type], or returns the id of the one already running for the couple.
  Future<String> start({
    required String coupleId,
    required String userId,
    required GameType type,
    required Map<String, dynamic> state,
  });

  /// Plays a turn on [session]: stores [state], passes the turn to the partner (or ends the game
  /// when [finish] is set). The partner gets a push when the game ends, or when it is their turn
  /// and they are not looking at the game (see [enterGame]). Throws if it was not this user's turn or the
  /// game changed in the meantime.
  Future<void> makeMove({
    required GameSession session,
    required String userId,
    required Map<String, dynamic> state,
    bool finish = false,
  });

  /// Stores [state] on [session] without a turn (either partner may do it), e.g. the next
  /// conversation card. Throws if the game changed in the meantime.
  Future<void> updateState({required GameSession session, required Map<String, dynamic> state});

  /// Tells the partner this user is looking at the [type] game, so a move made while they are
  /// there needs no push. Replaces whatever screen this user announced before.
  Future<void> enterGame({required String coupleId, required String userId, required GameType type});

  /// Takes the announcement back (screen closed or app in the background).
  Future<void> leaveGame({required String coupleId, required String userId});

  /// Ends the game for both partners.
  Future<void> finish(String sessionId);

  /// Seals and sends this user's answer for [round]; final once sent. [notify] tells the partner
  /// (used once, when the user has answered their last round). Throws if the couple key is missing.
  Future<void> submitAnswer({
    required GameSession session,
    required String userId,
    required int round,
    required Map<String, dynamic> content,
    bool notify = false,
  });

  /// This user's answers, plus the partner's for the rounds this user has answered too.
  Future<List<GameAnswer>> getAnswers(GameSession session);
}
