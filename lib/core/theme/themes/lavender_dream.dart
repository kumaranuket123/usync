import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../usync_theme_data.dart';

final class LavenderDreamTheme {
  static const String id = 'lavenderDream';
  static const String name = 'Lavender Dream';

  static final UsyncThemeData tokens = UsyncThemeData(
    primary: const Color(0xFFC77DFF),
    primarySoft: const Color(0xFFE8C5FF),
    secondary: const Color(0xFF9B59B6),
    bg1: const Color(0xFF0E0718),
    bg2: const Color(0xFF1A0F2E),
    bg3: const Color(0xFF0C051A),
    glass: AppColors.glass,
    glassBorder: AppColors.glassBorder,
    textPrimary: AppColors.textPrimary,
    textMuted: AppColors.textMuted,
    bgGradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0E0718), Color(0xFF1A0F2E), Color(0xFF0C051A)],
    ),
    primaryGradient: const LinearGradient(
      colors: [Color(0xFF9B59B6), Color(0xFFC77DFF)],
    ),
    gradientTextColors: const [Color(0xFFC77DFF), Color(0xFF9B59B6), Color(0xFFE8C5FF)],
    primaryGlow: [BoxShadow(color: const Color(0xFFC77DFF).withValues(alpha: 0.45), blurRadius: 30)],
    cardGlow: [BoxShadow(color: const Color(0xFF9B59B6).withValues(alpha: 0.15), blurRadius: 20)],
    orbGlow: [BoxShadow(color: const Color(0xFFC77DFF).withValues(alpha: 0.35), blurRadius: 50)],
  );

  static const List<Color> swatches = [
    Color(0xFFC77DFF), Color(0xFF9B59B6), Color(0xFFE8C5FF), Color(0xFF7B2FBE),
  ];

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF9B59B6), Color(0xFFC77DFF)],
  );
}
