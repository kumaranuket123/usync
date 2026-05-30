import 'package:equatable/equatable.dart';

class TouchEvent extends Equatable {
  const TouchEvent({
    required this.coupleId,
    required this.userId,
    required this.isActive,
    required this.timestamp,
  });

  final String   coupleId;
  final String   userId;
  final bool     isActive;
  final DateTime timestamp;

  @override
  List<Object?> get props => [coupleId, userId, isActive, timestamp];
}
