import '../../domain/entities/memory.dart';

class MemoryModel extends Memory {
  const MemoryModel({
    required super.id,
    required super.coupleId,
    required super.type,
    required super.thumbnailEmoji,
    required super.title,
    required super.createdAt,
    required super.createdByUserId,
    super.thumbnailUrl,
    super.isFavourited,
  });

  /// Row from the Supabase `memories` table.
  factory MemoryModel.fromRow(Map<String, dynamic> row) => MemoryModel(
    id:              row['id']                 as String,
    coupleId:        row['couple_id']          as String,
    type:            MemoryType.fromString(row['type'] as String),
    thumbnailEmoji:  row['thumbnail_emoji']    as String,
    title:           row['title']              as String,
    createdAt:       DateTime.parse(row['created_at'] as String),
    createdByUserId: row['created_by_user_id'] as String,
    thumbnailUrl:    row['thumbnail_url']      as String?,
    isFavourited:    row['is_favourited']      as bool? ?? false,
  );

  Map<String, dynamic> toRow() => {
    'couple_id':          coupleId,
    'type':               type.name,
    'thumbnail_emoji':    thumbnailEmoji,
    'title':              title,
    'created_by_user_id': createdByUserId,
    'thumbnail_url':      thumbnailUrl,
    'is_favourited':      isFavourited,
  };

  factory MemoryModel.fromEntity(Memory m) => MemoryModel(
    id:              m.id,
    coupleId:        m.coupleId,
    type:            m.type,
    thumbnailEmoji:  m.thumbnailEmoji,
    title:           m.title,
    createdAt:       m.createdAt,
    createdByUserId: m.createdByUserId,
    thumbnailUrl:    m.thumbnailUrl,
    isFavourited:    m.isFavourited,
  );
}
