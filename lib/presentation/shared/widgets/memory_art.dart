import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/memory.dart';

/// A memory's picture: the saved image when there is one, otherwise (or while
/// it loads, or if it fails to load) its emoji.
class MemoryArt extends StatelessWidget {
  const MemoryArt({
    super.key,
    required this.memory,
    required this.emojiSize,
    this.fill = false,
  });

  final Memory memory;
  final double emojiSize;
  /// Cover the whole area (cards) instead of fitting inside it (detail view).
  final bool   fill;

  @override
  Widget build(BuildContext context) {
    final emoji = Center(child: Text(memory.thumbnailEmoji, style: TextStyle(fontSize: emojiSize)));
    final url   = memory.thumbnailUrl;
    // A picture saved on this phone (older memories) is a file path, not a link.
    if (url != null && url.startsWith('/')) {
      return Image.file(
        File(url),
        fit:    fill ? BoxFit.cover : BoxFit.contain,
        width:  fill ? double.infinity : null,
        height: fill ? double.infinity : null,
        errorBuilder: (_, __, ___) => emoji,
      );
    }
    // The repository swaps the stored path for a signed URL; anything else
    // means signing failed, so show the emoji.
    if (url == null || !url.startsWith('http')) return emoji;

    return CachedNetworkImage(
      imageUrl:    url,
      // Signed URLs change on every refresh; the picture itself never does.
      cacheKey:    memory.id,
      fit:         fill ? BoxFit.cover : BoxFit.contain,
      width:       fill ? double.infinity : null,
      height:      fill ? double.infinity : null,
      placeholder: (_, __) => emoji,
      errorWidget: (_, __, ___) => emoji,
    );
  }
}
