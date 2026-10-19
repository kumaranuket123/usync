import 'package:flutter/material.dart';

/// Fixed EKG polyline with an animated scan-line travelling left → right.
class HeartbeatPainter extends CustomPainter {
  const HeartbeatPainter({required this.scanProgress, required this.color});

  final double scanProgress; // 0.0 – 1.0
  final Color  color;

  static const _points = <double>[
    0,   0.5,
    0.11,0.5,
    0.15,0.5,
    0.19,0.17,
    0.22,0.83,
    0.25,0.25,
    0.28,0.75,
    0.30,0.5,
    0.44,0.5,
    0.48,0.5,
    0.52,0.5,
    0.56,0.21,
    0.59,0.79,
    0.62,0.29,
    0.65,0.71,
    0.68,0.5,
    0.82,0.5,
    1.0, 0.5,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < _points.length; i += 2) {
      final x = _points[i] * size.width;
      final y = _points[i + 1] * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final scanX = scanProgress * size.width;

    // Dim path
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Bright portion up to scan line
    final clipRect = Rect.fromLTWH(0, 0, scanX, size.height);
    canvas.save();
    canvas.clipRect(clipRect);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(HeartbeatPainter old) =>
      old.scanProgress != scanProgress || old.color != color;
}
