import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../../../domain/entities/memory.dart';
import '../../../domain/repositories/i_memory_repository.dart';

/// A memory's picture: the saved image when there is one, otherwise (or while
/// it loads, or if it fails to load) its emoji.
class MemoryArt extends StatefulWidget {
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
  State<MemoryArt> createState() => _MemoryArtState();
}

class _MemoryArtState extends State<MemoryArt> {
  Future<Uint8List?>? _image;

  /// Pictures are stored encrypted, so they are downloaded and opened on this phone rather than loaded
  /// from a link. A picture already saved on the phone is a file path and is shown from there.
  Future<Uint8List?>? _load() {
    final url = widget.memory.thumbnailUrl;
    if (url == null || url.isEmpty || url.startsWith('/')) return null;
    return getIt<IMemoryRepository>().loadImage(widget.memory);
  }

  @override
  void initState() {
    super.initState();
    _image = _load();
  }

  @override
  void didUpdateWidget(MemoryArt old) {
    super.didUpdateWidget(old);
    // The picture itself never changes for a memory; only a different memory or a new place for it reloads.
    if (old.memory.id != widget.memory.id || old.memory.thumbnailUrl != widget.memory.thumbnailUrl) _image = _load();
  }

  @override
  Widget build(BuildContext context) {
    final emoji = Center(child: Text(widget.memory.thumbnailEmoji, style: TextStyle(fontSize: widget.emojiSize)));
    final url   = widget.memory.thumbnailUrl;
    final fit   = widget.fill ? BoxFit.cover : BoxFit.contain;
    final width = widget.fill ? double.infinity : null;
    final height = widget.fill ? double.infinity : null;

    if (url != null && url.startsWith('/')) {
      return Image.file(File(url), fit: fit, width: width, height: height, errorBuilder: (_, __, ___) => emoji);
    }
    if (_image == null) return emoji;
    return FutureBuilder<Uint8List?>(
      future: _image,
      builder: (_, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return emoji;
        return Image.memory(bytes, fit: fit, width: width, height: height, gaplessPlayback: true, errorBuilder: (_, __, ___) => emoji);
      },
    );
  }
}
