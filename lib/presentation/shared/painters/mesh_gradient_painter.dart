import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Three radial gradient blobs that create the ambient background mesh.
class MeshGradientPainter extends CustomPainter {
  const MeshGradientPainter({required this.colors});
  final List<Color> colors; // [primary, secondary, bg]

  @override
  void paint(Canvas canvas, Size size) {
    final primary   = colors.isNotEmpty ? colors[0] : const Color(0xFFFF2D78);
    final secondary = colors.length > 1 ? colors[1] : const Color(0xFF9D4EDD);
    final accent    = colors.length > 2 ? colors[2] : const Color(0xFF00D4FF);

    void _drawBlob(Alignment align, Color color, double radius) {
      final center = align.withinRect(Offset.zero & size);
      final paint  = Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [color.withOpacity(0.08), color.withOpacity(0)],
        );
      canvas.drawCircle(center, radius, paint);
    }

    _drawBlob(const Alignment(0.7, -0.7),  primary,   size.width * 0.8);
    _drawBlob(const Alignment(-0.7, 0.7),  secondary, size.width * 0.7);
    _drawBlob(const Alignment(0.0,  0.3),  accent,    size.width * 0.6);
  }

  @override
  bool shouldRepaint(MeshGradientPainter old) => old.colors != colors;
}
