import '../../domain/entities/bucket_item.dart';

class BucketItemModel extends BucketItem {
  const BucketItemModel({
    required super.id,
    required super.coupleId,
    required super.title,
    required super.emoji,
    required super.createdAt,
    super.note,
    super.createdBy,
    super.doneAt,
    super.doneBy,
  });

  /// Row from the Supabase `bucket_items` table.
  factory BucketItemModel.fromRow(Map<String, dynamic> row) => BucketItemModel(
    id:        row['id']         as String,
    coupleId:  row['couple_id']  as String,
    title:     row['title']      as String,
    emoji:     (row['emoji'] as String?) ?? '✨',
    note:      row['note']       as String?,
    createdBy: row['created_by'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    doneAt:    row['done_at'] == null ? null : DateTime.parse(row['done_at'] as String),
    doneBy:    row['done_by']    as String?,
  );
}
