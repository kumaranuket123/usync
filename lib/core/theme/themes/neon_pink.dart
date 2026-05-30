import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../usync_theme_data.dart';

final class NeonPinkTheme {
  static const String id = 'neonPink';
  static const String name = 'Neon Pink';

  static final UsyncThemeData tokens = UsyncThemeData(
    primary: const Color(0xFFFF2D78),
    primarySoft: const Color(0xFFFF6EC7),
    secondary: const Color(0xFF6B1FB2),
    bg1: const Color(0xFF120008),
    bg2: const Color(0xFF1E0010),
    bg3: const Color(0xFF0A0015),
    glass: AppColors.glass,
    glassBorder: AppColors.glassBorder,
    textPrimary: AppColors.textPrimary,
    textMuted: AppColors.textMuted,
    bgGradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF120008), Color(0xFF1E0010), Color(0xFF0A0015)],
    ),
    primaryGradient: const LinearGradient(
      colors: [Color(0xFFFF2D78), Color(0xFF6B1FB2)],
    ),
    gradientTextColors: const [Color(0xFFFF6EC7), Color(0xFFFFB3D9), Color(0xFFFF2D78)],
    primaryGlow: [BoxShadow(color: const Color(0xFFFF2D78).withOpacity(0.55), blurRadius: 30)],
    cardGlow: [BoxShadow(color: const Color(0xFF6B1FB2).withOpacity(0.15), blurRadius: 20)],
    orbGlow: [BoxShadow(color: const Color(0xFFFF2D78).withOpacity(0.45), blurRadius: 50)],
  );

  static const List<Color> swatches = [
    Color(0xFFFF2D78), Color(0xFFFF6EC7), Color(0xFF6B1FB2), Color(0xFFFFB3D9),
  ];

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFFFF2D78), Color(0xFF6B1FB2)],
  );
}
