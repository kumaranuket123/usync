import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/utils/particle_math.dart';

/// Tick-driven particle painter. Feed it [tick] from an AnimationController
/// to move particles upward and loop them.
class ParticlePainter extends CustomPainter {
  const ParticlePainter({required this.particles, required this.tick});

  final List<ParticleData> particles;
  final double             tick; // 0.0 – 1.0 looping

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      // Each particle has its own phase offset derived from delayMs.
      final phase     = p.delayMs / 8000.0;
      final t         = ((tick + phase) % 1.0);

      final x = p.x * size.width;
      final y = size.height - (t * (size.height + 40));

      final opacity = switch (t) {
        < 0.1 => t / 0.1,
        > 0.9 => (1.0 - t) / 0.1,
        _     => p.opacity,
      };

      final paint = Paint()
        ..color      = p.color.withOpacity(opacity.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size);

      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(ParticlePainter old) => old.tick != tick;
}
