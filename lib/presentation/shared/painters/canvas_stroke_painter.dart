import 'package:flutter/material.dart';

import '../../../domain/entities/canvas_stroke.dart';

class CanvasStrokePainter extends CustomPainter {
  const CanvasStrokePainter({
    required this.strokes,
    this.activeStroke,
  });

  /// Committed strokes in drawing order (later strokes, incl. erasers, paint on top).
  final List<CanvasStroke> strokes;
  final CanvasStroke?      activeStroke;

  // Strokes are immutable (appendPoint/complete create new objects), so the
  // built path can be cached per instance instead of rebuilt every frame.
  static final _paths = Expando<Path>('canvasStrokePath');

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());

    for (final stroke in strokes) {
      if (stroke.id == activeStroke?.id) continue;
      _drawStroke(canvas, stroke);
    }
    if (activeStroke != null) _drawStroke(canvas, activeStroke!);

    canvas.restore();
  }

  void _drawStroke(Canvas canvas, CanvasStroke stroke) {
    final pts = stroke.points;
    if (pts.isEmpty) return;

    final paint = Paint()
      ..strokeWidth = stroke.width
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round
      ..style       = PaintingStyle.stroke
      ..blendMode   = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;

    if (!stroke.isEraser) {
      paint
        ..color      = stroke.color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    }

    // Single point → draw as dot
    if (pts.length == 1) {
      canvas.drawCircle(pts.first, stroke.width / 2, paint..style = PaintingStyle.fill);
      return;
    }

    canvas.drawPath(_paths[stroke] ??= _buildPath(pts), paint);
  }

  /// Smooth quadratic bezier through midpoints — eliminates cross-hatch artifacts.
  static Path _buildPath(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final mid = Offset(
        (pts[i].dx + pts[i + 1].dx) / 2,
        (pts[i].dy + pts[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }

  @override
  bool shouldRepaint(CanvasStrokePainter old) =>
      !identical(old.strokes, strokes) || !identical(old.activeStroke, activeStroke);
}
