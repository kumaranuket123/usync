import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../usync_theme_data.dart';

final class MidnightPurpleTheme {
  static const String id = 'midnightPurple';
  static const String name = 'Midnight Purple';

  static final UsyncThemeData tokens = UsyncThemeData(
    primary: AppColors.pink,
    primarySoft: AppColors.pinkLight,
    secondary: AppColors.purple,
    bg1: AppColors.bg1,
    bg2: AppColors.bg2,
    bg3: AppColors.bg3,
    glass: AppColors.glass,
    glassBorder: AppColors.glassBorder,
    textPrimary: AppColors.textPrimary,
    textMuted: AppColors.textMuted,
    bgGradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: [0.0, 0.4, 1.0],
      colors: [AppColors.bg1, AppColors.bg2, AppColors.bg3],
    ),
    primaryGradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.pink, AppColors.purple],
    ),
    gradientTextColors: const [AppColors.pinkLight, AppColors.lavender, AppColors.cyan],
    primaryGlow: [
      BoxShadow(color: AppColors.pink.withValues(alpha: 0.45), blurRadius: 30),
      BoxShadow(color: AppColors.pink.withValues(alpha: 0.20), blurRadius: 60),
    ],
    cardGlow: [
      BoxShadow(color: AppColors.purple.withValues(alpha: 0.15), blurRadius: 20),
    ],
    orbGlow: [
      BoxShadow(color: AppColors.pink.withValues(alpha: 0.35), blurRadius: 50),
      BoxShadow(color: AppColors.purple.withValues(alpha: 0.20), blurRadius: 100),
    ],
  );

  static const List<Color> swatches = [
    AppColors.purple, AppColors.pink, AppColors.cyan, AppColors.lavender,
  ];

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF2D1B69), Color(0xFF11998E)],
  );
}
