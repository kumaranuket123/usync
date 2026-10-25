import 'package:equatable/equatable.dart';

class Couple extends Equatable {
  const Couple({
    required this.id,
    required this.userAId,
    required this.userBId,
    required this.pairedAt,
    this.streakDays    = 0,
    this.totalMoments  = 0,
    this.disconnectRequestedBy,
    this.disconnectedAt,
  });

  final String   id;
  final String   userAId;
  final String   userBId;
  final DateTime pairedAt;
  final int      streakDays;
  final int      totalMoments;
  /// uid of the partner who asked to disconnect; null when no request is pending.
  final String?  disconnectRequestedBy;
  final DateTime? disconnectedAt;

  bool get isDisconnected => disconnectedAt != null;

  int get daysTogether => DateTime.now().difference(pairedAt).inDays;

  String partnerIdFor(String userId) =>
      userId == userAId ? userBId : userAId;

  @override
  List<Object?> get props => [id, userAId, userBId, pairedAt, streakDays, totalMoments, disconnectRequestedBy, disconnectedAt];
}
