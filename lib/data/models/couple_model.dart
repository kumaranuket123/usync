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
    userAId:      row['user_a_id']         as String,
    userBId:      row['user_b_id']         as String,
    pairedAt:     DateTime.parse(row['paired_at'] as String),
    streakDays:   (row['streak_days']      as num?)?.toInt() ?? 0,
    totalMoments: (row['total_moments']    as num?)?.toInt() ?? 0,
    disconnectRequestedBy: row['disconnect_requested_by'] as String?,
    disconnectedAt: row['disconnected_at'] == null
        ? null
        : DateTime.parse(row['disconnected_at'] as String),
  );
}
