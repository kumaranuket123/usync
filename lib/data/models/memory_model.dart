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

  factory MemoryModel.fromJson(String id, Map<String, dynamic> json) => MemoryModel(
    id:              id,
    coupleId:        json['coupleId']        as String,
    type:            MemoryType.fromString(json['type'] as String),
    thumbnailEmoji:  json['thumbnailEmoji']  as String,
    title:           json['title']           as String,
    createdAt:       DateTime.parse(json['createdAt'] as String),
    createdByUserId: json['createdByUserId'] as String,
    thumbnailUrl:    json['thumbnailUrl']    as String?,
    isFavourited:    json['isFavourited']    as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'coupleId':        coupleId,
    'type':            type.name,
    'thumbnailEmoji':  thumbnailEmoji,
    'title':           title,
    'createdAt':       createdAt.toIso8601String(),
    'createdByUserId': createdByUserId,
    'thumbnailUrl':    thumbnailUrl,
    'isFavourited':    isFavourited,
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
