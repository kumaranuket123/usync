import 'package:flutter/material.dart';

import '../../domain/entities/canvas_stroke.dart';

class CanvasStrokeModel extends CanvasStroke {
  const CanvasStrokeModel({
    required super.id,
    required super.coupleId,
    required super.userId,
    required super.color,
    required super.width,
    required super.timestamp,
    super.points,
    super.isEraser,
    super.isComplete,
  });

  /// Zero-padded so lexicographic order == chunk order.
  static String chunkKey(int seq) => seq.toString().padLeft(6, '0');

  factory CanvasStrokeModel.fromJson(String id, Map<String, dynamic> json) {
    final points = <Offset>[];

    // Live format: chunks/{paddedSeq} = [x0, y0, x1, y1, …]
    final rawChunks = json['chunks'];
    if (rawChunks is Map) {
      final keys = rawChunks.keys.map((k) => k.toString()).toList()..sort();
      for (final k in keys) {
        _addFlat(points, rawChunks[k]);
      }
    } else if (rawChunks is List) {
      for (final c in rawChunks) {
        _addFlat(points, c);
      }
    }

    // Legacy format: points as a List or push-key Map of {x, y}.
    final rawPoints = json['points'];
    if (points.isEmpty && rawPoints != null) {
      final items = rawPoints is Map
          ? (rawPoints.entries.toList()
                ..sort((a, b) => a.key.toString().compareTo(b.key.toString())))
              .map((e) => e.value)
          : (rawPoints as List);
      for (final p in items) {
        if (p is! Map) continue;
        points.add(Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()));
      }
    }

    return CanvasStrokeModel(
      id:         id,
      coupleId:   json['coupleId'] as String,
      userId:     json['userId']   as String,
      color:      Color(int.parse(json['color'] as String)),
      width:      (json['width']   as num).toDouble(),
      timestamp:  DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      points:     points,
      isEraser:   json['isEraser']   as bool? ?? false,
      isComplete: json['isComplete'] as bool? ?? false,
    );
  }

  static void _addFlat(List<Offset> out, Object? raw) {
    if (raw is! List) return;
    for (var i = 0; i + 1 < raw.length; i += 2) {
      final x = raw[i], y = raw[i + 1];
      if (x is num && y is num) out.add(Offset(x.toDouble(), y.toDouble()));
    }
  }

  Map<String, dynamic> toJson() => {
    'coupleId':   coupleId,
    'userId':     userId,
    'color':      color.toARGB32().toString(),
    'width':      width,
    'timestamp':  timestamp.millisecondsSinceEpoch,
    'isEraser':   isEraser,
    'isComplete': isComplete,
    'points':     points.map((o) => {'x': o.dx, 'y': o.dy}).toList(),
  };
}
