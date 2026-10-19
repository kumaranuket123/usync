import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../painters/conic_orb_painter.dart';
import 'pulse_rings.dart';

class PartnerOrb extends StatefulWidget {
  const PartnerOrb({
    super.key,
    required this.avatarEmoji,
    this.isOnline   = false,
    this.size        = 150.0,
    this.moodBadge,
    this.orbColors,
  });

  final String       avatarEmoji;
  final bool         isOnline;
  final double       size;
  final String?      moodBadge;
  final List<Color>? orbColors;

  @override
  State<PartnerOrb> createState() => _PartnerOrbState();
}

class _PartnerOrbState extends State<PartnerOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return SizedBox(
      width:  size + 120,
      height: size + 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulse rings behind orb
          PulseRings(
            color: AppColors.pink,
            count: 3,
            size:  size + 120,
            staggerMs: 1100,
          ),

          // Spinning conic ring
          AnimatedBuilder(
            animation: _spin,
            builder: (_, __) => CustomPaint(
              size: Size(size, size),
              painter: ConicOrbPainter(
                angle:  _spin.value * 2 * pi,
                colors: widget.orbColors ?? const [
                  AppColors.pink, AppColors.purple,
                  AppColors.cyan, AppColors.purple, AppColors.pink,
                ],
              ),
            ),
          ),

          // Inner dark circle with avatar
          Container(
            width: size * 0.79,
            height: size * 0.79,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [AppColors.bg2, AppColors.bg1]),
              boxShadow: [
                BoxShadow(color: AppColors.pink.withValues(alpha: 0.35), blurRadius: 50),
                BoxShadow(color: AppColors.purple.withValues(alpha: 0.20), blurRadius: 100),
              ],
            ),
            child: Center(
              child: Text(
                widget.avatarEmoji,
                style: TextStyle(fontSize: size * 0.33),
              ),
            ),
          ),

          // Online badge
          Positioned(
            bottom: (size + 120) / 2 - size / 2 - 2,
            right:  (size + 120) / 2 - size / 2 + 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.pink, AppColors.purple],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.bg1, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color:  widget.isOnline ? AppColors.online : AppColors.offline,
                      shape:  BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.isOnline ? 'online' : 'away',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
