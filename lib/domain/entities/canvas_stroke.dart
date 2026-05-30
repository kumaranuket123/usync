import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class CanvasStroke extends Equatable {
  const CanvasStroke({
    required this.id,
    required this.coupleId,
    required this.userId,
    required this.color,
    required this.width,
    required this.timestamp,
    this.points     = const [],
    this.isEraser   = false,
    this.isComplete = false,
  });

  final String       id;
  final String       coupleId;
  final String       userId;
  final Color        color;
  final double       width;
  final DateTime     timestamp;
  final List<Offset> points;
  final bool         isEraser;
  final bool         isComplete;

  CanvasStroke appendPoint(Offset point) => CanvasStroke(
    id:         id,
    coupleId:   coupleId,
    userId:     userId,
    color:      color,
    width:      width,
    timestamp:  timestamp,
    points:     [...points, point],
    isEraser:   isEraser,
    isComplete: isComplete,
  );

  CanvasStroke complete() => CanvasStroke(
    id:         id,
    coupleId:   coupleId,
    userId:     userId,
    color:      color,
    width:      width,
    timestamp:  timestamp,
    points:     points,
    isEraser:   isEraser,
    isComplete: true,
  );

  @override
  List<Object?> get props => [id, userId, isComplete, points.length];
}
