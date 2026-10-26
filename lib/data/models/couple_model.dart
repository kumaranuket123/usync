import '../../domain/entities/couple.dart';

class CoupleModel extends Couple {
  const CoupleModel({
    required super.id,
    required super.userAId,
    required super.userBId,
    required super.pairedAt,
    super.streakDays,
    super.totalMoments,
    super.disconnectRequestedBy,
    super.disconnectedAt,
  });

  /// Row from the Supabase `couples` table.
  factory CoupleModel.fromRow(Map<String, dynamic> row) => CoupleModel(
    id:           row['id']                as String,
    userAId:      (row['user_a_id'] as String?) ?? '', // null once that user deleted their account
    userBId:      (row['user_b_id'] as String?) ?? '',
    pairedAt:     DateTime.parse(row['paired_at'] as String),
    streakDays:   _liveStreak(row),
    totalMoments: (row['total_moments']    as num?)?.toInt() ?? 0,
    disconnectRequestedBy: row['disconnect_requested_by'] as String?,
    disconnectedAt: row['disconnected_at'] == null
        ? null
        : DateTime.parse(row['disconnected_at'] as String),
  );

  /// The stored streak only changes when someone is active, so a streak whose
  /// last day is older than yesterday (UTC) has already ended.
  static int _liveStreak(Map<String, dynamic> row) {
    final stored = (row['streak_days'] as num?)?.toInt() ?? 0;
    final last   = row['streak_last_day'] as String?;
    if (last == null) return 0;
    final now       = DateTime.now().toUtc();
    final today     = DateTime.utc(now.year, now.month, now.day);
    final lastDay   = DateTime.parse(last); // 'YYYY-MM-DD', parsed as UTC
    return today.difference(lastDay).inDays <= 1 ? stored : 0;
  }
}
