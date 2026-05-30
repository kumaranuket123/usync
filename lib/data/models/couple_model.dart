import '../../domain/entities/couple.dart';

class CoupleModel extends Couple {
  const CoupleModel({
    required super.id,
    required super.userAId,
    required super.userBId,
    required super.pairedAt,
    super.streakDays,
    super.totalMoments,
  });

  factory CoupleModel.fromJson(String id, Map<String, dynamic> json) => CoupleModel(
    id:           id,
    userAId:      json['userAId']      as String,
    userBId:      json['userBId']      as String,
    pairedAt:     DateTime.parse(json['pairedAt'] as String),
    streakDays:   (json['streakDays']   as num?)?.toInt() ?? 0,
    totalMoments: (json['totalMoments'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'userAId':      userAId,
    'userBId':      userBId,
    'pairedAt':     pairedAt.toIso8601String(),
    'streakDays':   streakDays,
    'totalMoments': totalMoments,
  };
}
