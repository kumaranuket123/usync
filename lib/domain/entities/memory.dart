import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum MemoryType {
  canvas,
  touch,
  mood,
  milestone;

  String get tagLabel => switch (this) {
    MemoryType.canvas    => 'Canvas',
    MemoryType.touch     => 'Touch',
    MemoryType.mood      => 'Mood',
    MemoryType.milestone => 'Milestone',
  };

  String get defaultEmoji => switch (this) {
    MemoryType.canvas    => '🌸',
    MemoryType.touch     => '👆',
    MemoryType.mood      => '💭',
    MemoryType.milestone => '🎉',
  };

  Color get tagColor => switch (this) {
    MemoryType.canvas    => const Color(0xFFFF6EC7),
    MemoryType.touch     => const Color(0xFFC77DFF),
    MemoryType.mood      => const Color(0xFF00D4FF),
    MemoryType.milestone => const Color(0xFFFFD700),
  };

  Color get tagBackground => switch (this) {
    MemoryType.canvas    => const Color(0x26FF6EC7),
    MemoryType.touch     => const Color(0x26C77DFF),
    MemoryType.mood      => const Color(0x1F00D4FF),
    MemoryType.milestone => const Color(0x1FFFD700),
  };

  static MemoryType fromString(String value) =>
      MemoryType.values.firstWhere((e) => e.name == value, orElse: () => MemoryType.mood);
}

class Memory extends Equatable {
  const Memory({
    required this.id,
    required this.coupleId,
    required this.type,
    required this.thumbnailEmoji,
    required this.title,
    required this.createdAt,
    required this.createdByUserId,
    this.thumbnailUrl,
    this.isFavourited = false,
    this.imageArchived = false,
  });

  final String     id;
  final String     coupleId;
  final MemoryType type;
  final String     thumbnailEmoji;
  final String     title;
  final DateTime   createdAt;
  final String     createdByUserId;
  final String?    thumbnailUrl;
  final bool       isFavourited;
  /// The picture was moved off the server (see `archive_memory_image`); it now
  /// only exists on the phones that saved it.
  final bool       imageArchived;

  Memory copyWith({bool? isFavourited, String? thumbnailUrl}) {
    return Memory(
      id:              id,
      coupleId:        coupleId,
      type:            type,
      thumbnailEmoji:  thumbnailEmoji,
      title:           title,
      createdAt:       createdAt,
      createdByUserId: createdByUserId,
      thumbnailUrl:    thumbnailUrl    ?? this.thumbnailUrl,
      isFavourited:    isFavourited    ?? this.isFavourited,
      imageArchived:   imageArchived,
    );
  }

  @override
  List<Object?> get props => [id, coupleId, type, title, createdAt, isFavourited, imageArchived, thumbnailUrl];
}
