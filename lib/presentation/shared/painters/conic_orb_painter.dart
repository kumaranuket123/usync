import 'dart:math';

import 'package:flutter/material.dart';

/// Spinning conic-gradient ring used for the logo and partner orb.
class ConicOrbPainter extends CustomPainter {
  const ConicOrbPainter({required this.angle, required this.colors});

  final double       angle;  // rotation in radians, driven by AnimationController
  final List<Color>  colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);

    final paint = Paint()
      ..shader = SweepGradient(
        colors: colors.isEmpty
            ? [
                const Color(0xFFFF2D78),
                const Color(0xFF9D4EDD),
                const Color(0xFF00D4FF),
                const Color(0xFF9D4EDD),
                const Color(0xFFFF2D78),
              ]
            : colors,
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ConicOrbPainter old) => old.angle != angle;
}
