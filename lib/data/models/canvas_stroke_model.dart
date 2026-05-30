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

  factory CanvasStrokeModel.fromJson(String id, Map<String, dynamic> json) {
    // RTDB push() stores points as Map<autoKey, {x,y}>, not a List.
    final rawPoints = json['points'];
    final points = <Offset>[];
    if (rawPoints is Map) {
      // Sort by Firebase push key (lexicographic = chronological) before building points
      final entries = rawPoints.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        final m = Map<String, dynamic>.from(entry.value as Map);
        points.add(Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble()));
      }
    } else if (rawPoints is List) {
      for (final p in rawPoints) {
        final m = Map<String, dynamic>.from(p as Map);
        points.add(Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble()));
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

  Map<String, dynamic> toJson() => {
    'coupleId':   coupleId,
    'userId':     userId,
    'color':      color.value.toString(),
    'width':      width,
    'timestamp':  timestamp.millisecondsSinceEpoch,
    'isEraser':   isEraser,
    'isComplete': isComplete,
    'points':     points.map((o) => {'x': o.dx, 'y': o.dy}).toList(),
  };
}
