import 'dart:math';

import 'package:flutter/material.dart';

/// Immutable description of a single particle.
class ParticleData {
  const ParticleData({
    required this.x,
    required this.color,
    required this.size,
    required this.opacity,
    required this.durationMs,
    required this.delayMs,
  });

  final double x;          // 0.0 – 1.0 (fraction of canvas width)
  final Color  color;
  final double size;        // radius in logical pixels
  final double opacity;
  final int    durationMs;
  final int    delayMs;
}

abstract final class ParticleMath {
  static final _rng = Random();

  static List<ParticleData> generate({
    required int count,
    required List<Color> colors,
    double minSize = 1.5,
    double maxSize = 5.0,
    int minDurationMs = 6000,
    int maxDurationMs = 14000,
  }) {
    return List.generate(count, (_) {
      final size = minSize + _rng.nextDouble() * (maxSize - minSize);
      return ParticleData(
        x:          _rng.nextDouble(),
        color:      colors[_rng.nextInt(colors.length)],
        size:       size,
        opacity:    0.2 + _rng.nextDouble() * 0.6,
        durationMs: minDurationMs + _rng.nextInt(maxDurationMs - minDurationMs),
        delayMs:    _rng.nextInt(8000),
      );
    });
  }
}
