import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppGradients {
  // ── Background ────────────────────────────────────────────────
  static const LinearGradient background = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.4, 1.0],
    colors: [AppColors.bg1, AppColors.bg2, AppColors.bg3],
  );

  // ── Primary action ────────────────────────────────────────────
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.pink, AppColors.purple],
  );

  // ── Gradient text (3-stop) ────────────────────────────────────
  static const LinearGradient gradientText = LinearGradient(
    colors: [AppColors.pinkLight, AppColors.lavender, AppColors.cyan],
  );

  static const LinearGradient gradientText2 = LinearGradient(
    colors: [AppColors.pinkLight, AppColors.lavender],
  );

  // ── Orb ───────────────────────────────────────────────────────
  static const SweepGradient orb = SweepGradient(
    colors: [
      AppColors.pink,
      AppColors.purple,
      AppColors.cyan,
      AppColors.purple,
      AppColors.pink,
    ],
  );

  // ── Memory card overlays ──────────────────────────────────────
  static LinearGradient memoryCanvas = LinearGradient(
    colors: [AppColors.pink.withOpacity(0.15), AppColors.purple.withOpacity(0.15)],
  );

  static LinearGradient memoryTouch = LinearGradient(
    colors: [AppColors.cyan.withOpacity(0.10), AppColors.purple.withOpacity(0.15)],
  );

  static LinearGradient memoryMood = LinearGradient(
    colors: [AppColors.gold.withOpacity(0.08), AppColors.pink.withOpacity(0.12)],
  );

  static LinearGradient memoryMilestone = LinearGradient(
    colors: [AppColors.cyan.withOpacity(0.08), const Color(0xFF0B4EDD).withOpacity(0.15)],
  );

  // ── Footer overlay (bottom-up fade) ───────────────────────────
  static LinearGradient footerOverlay = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [AppColors.bg1, AppColors.bg1.withOpacity(0)],
  );

  // ── Header overlay (top-down fade) ───────────────────────────
  static LinearGradient headerOverlay = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.bg1.withOpacity(0.95), AppColors.bg1.withOpacity(0)],
  );
}
