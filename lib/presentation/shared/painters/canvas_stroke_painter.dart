import 'package:flutter/material.dart';

import '../../../domain/entities/canvas_stroke.dart';

class CanvasStrokePainter extends CustomPainter {
  const CanvasStrokePainter({
    required this.strokes,
    this.activeStroke,
  });

  final List<CanvasStroke> strokes;
  final CanvasStroke?      activeStroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());

    // Deduplicate by ID — last entry wins (most up-to-date points).
    final byId = <String, CanvasStroke>{};
    for (final s in strokes) { byId[s.id] = s; }
    if (activeStroke != null) byId[activeStroke!.id] = activeStroke!;

    for (final stroke in byId.values) {
      if (stroke.points.isEmpty) continue;
      _drawStroke(canvas, stroke);
    }

    canvas.restore();
  }

  void _drawStroke(Canvas canvas, CanvasStroke stroke) {
    if (stroke.points.isEmpty) return;

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
    if (stroke.points.length == 1) {
      canvas.drawCircle(
        stroke.points.first,
        stroke.width / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final pts  = stroke.points;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);

    // Smooth quadratic bezier through midpoints — eliminates cross-hatch artifacts
    for (var i = 0; i < pts.length - 1; i++) {
      final mid = Offset(
        (pts[i].dx + pts[i + 1].dx) / 2,
        (pts[i].dy + pts[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CanvasStrokePainter _) => true;
}
