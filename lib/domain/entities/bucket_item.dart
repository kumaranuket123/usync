import 'package:equatable/equatable.dart';

/// One thing the couple wants to do together.
class BucketItem extends Equatable {
  const BucketItem({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.emoji,
    required this.createdAt,
    this.note,
    this.createdBy,
    this.doneAt,
    this.doneBy,
  });

  final String    id;
  final String    coupleId;
  final String    title;
  final String    emoji;
  final String?   note;
  final String?   createdBy;
  final DateTime  createdAt;
  /// When it was ticked off; null while it is still to do.
  final DateTime? doneAt;
  final String?   doneBy;

  bool get isDone => doneAt != null;

  @override
  List<Object?> get props => [id, title, emoji, note, doneAt, doneBy];
}
