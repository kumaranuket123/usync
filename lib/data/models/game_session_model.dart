import '../../domain/entities/game_session.dart';

class GameSessionModel {
  const GameSessionModel._();

  /// Row from the Supabase `game_sessions` table; null for a game kind this app version does not know.
  static GameSession? fromRow(Map<String, dynamic> row) {
    final type = GameType.fromKey(row['game_type'] as String);
    if (type == null) return null;
    return GameSession(
      id:         row['id']        as String,
      coupleId:   row['couple_id'] as String,
      type:       type,
      isActive:   row['status'] == 'active',
      state:      Map<String, dynamic>.from(row['state'] as Map? ?? const {}),
      version:    row['version']   as int,
      updatedAt:  DateTime.parse(row['updated_at'] as String),
      turnUserId: row['turn_user_id'] as String?,
      createdBy:  row['created_by']   as String?,
    );
  }
}
