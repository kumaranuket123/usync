import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../usync_theme_data.dart';

final class SunsetGlowTheme {
  static const String id = 'sunsetGlow';
  static const String name = 'Sunset Glow';

  static final UsyncThemeData tokens = UsyncThemeData(
    primary: const Color(0xFFFF416C),
    primarySoft: const Color(0xFFFF8C94),
    secondary: const Color(0xFFFF4B2B),
    bg1: const Color(0xFF1A0808),
    bg2: const Color(0xFF2A0A00),
    bg3: const Color(0xFF120505),
    glass: AppColors.glass,
    glassBorder: AppColors.glassBorder,
    textPrimary: AppColors.textPrimary,
    textMuted: AppColors.textMuted,
    bgGradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1A0808), Color(0xFF2A0A00), Color(0xFF120505)],
    ),
    primaryGradient: const LinearGradient(
      colors: [Color(0xFFFF416C), Color(0xFFFF4B2B), Color(0xFFFFA500)],
    ),
    gradientTextColors: const [Color(0xFFFF416C), Color(0xFFFF4B2B), Color(0xFFFFD700)],
    primaryGlow: [BoxShadow(color: const Color(0xFFFF416C).withOpacity(0.45), blurRadius: 30)],
    cardGlow: [BoxShadow(color: const Color(0xFFFF4B2B).withOpacity(0.15), blurRadius: 20)],
    orbGlow: [BoxShadow(color: const Color(0xFFFF416C).withOpacity(0.35), blurRadius: 50)],
  );

  static const List<Color> swatches = [
    Color(0xFFFF416C), Color(0xFFFF4B2B), Color(0xFFFFA500), Color(0xFFFFD700),
  ];

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFFFF416C), Color(0xFFFF4B2B), Color(0xFFFFA500)],
  );
}
