import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/particle_math.dart';
import '../painters/particle_painter.dart';

class ParticleField extends StatefulWidget {
  const ParticleField({
    super.key,
    this.count  = 30,
    this.colors = const [
      AppColors.pink, AppColors.pinkLight, AppColors.purple,
      AppColors.lavender, AppColors.cyan,
    ],
  });

  final int         count;
  final List<Color> colors;

  @override
  State<ParticleField> createState() => _ParticleFieldState();
}

class _ParticleFieldState extends State<ParticleField> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<ParticleData>  _particles;

  @override
  void initState() {
    super.initState();
    _particles = ParticleMath.generate(count: widget.count, colors: widget.colors);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: ParticlePainter(particles: _particles, tick: _ctrl.value),
        child: const SizedBox.expand(),
      ),
    );
  }
}
