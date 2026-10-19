import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../usync_theme_data.dart';

final class OceanBlueTheme {
  static const String id = 'oceanBlue';
  static const String name = 'Ocean Blue';

  static final UsyncThemeData tokens = UsyncThemeData(
    primary: const Color(0xFF00D4FF),
    primarySoft: const Color(0xFF7FEFFF),
    secondary: const Color(0xFF0575E6),
    bg1: const Color(0xFF010B18),
    bg2: const Color(0xFF021B79),
    bg3: const Color(0xFF010B18),
    glass: AppColors.glass,
    glassBorder: AppColors.glassBorder,
    textPrimary: AppColors.textPrimary,
    textMuted: AppColors.textMuted,
    bgGradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF010B18), Color(0xFF021B79), Color(0xFF010B18)],
    ),
    primaryGradient: const LinearGradient(
      colors: [Color(0xFF0575E6), Color(0xFF021B79)],
    ),
    gradientTextColors: const [Color(0xFF00D4FF), Color(0xFF7FEFFF), Color(0xFF0575E6)],
    primaryGlow: [BoxShadow(color: const Color(0xFF00D4FF).withValues(alpha: 0.50), blurRadius: 30)],
    cardGlow: [BoxShadow(color: const Color(0xFF0575E6).withValues(alpha: 0.15), blurRadius: 20)],
    orbGlow: [BoxShadow(color: const Color(0xFF00D4FF).withValues(alpha: 0.40), blurRadius: 50)],
  );

  static const List<Color> swatches = [
    Color(0xFF0575E6), Color(0xFF00D4FF), Color(0xFF021B79), Color(0xFF7FEFFF),
  ];

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF0575E6), Color(0xFF021B79)],
  );
}
