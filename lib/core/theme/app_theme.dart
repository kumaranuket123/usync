import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
import 'themes/lavender_dream.dart';
import 'themes/midnight_purple.dart';
import 'themes/neon_pink.dart';
import 'themes/ocean_blue.dart';
import 'themes/sunset_glow.dart';
import 'usync_theme_data.dart';

abstract final class AppTheme {
  static const Map<String, String> themeNames = {
    MidnightPurpleTheme.id: MidnightPurpleTheme.name,
    NeonPinkTheme.id: NeonPinkTheme.name,
    OceanBlueTheme.id: OceanBlueTheme.name,
    LavenderDreamTheme.id: LavenderDreamTheme.name,
    SunsetGlowTheme.id: SunsetGlowTheme.name,
  };

  static UsyncThemeData tokensFor(String id) => switch (id) {
    NeonPinkTheme.id      => NeonPinkTheme.tokens,
    OceanBlueTheme.id     => OceanBlueTheme.tokens,
    LavenderDreamTheme.id => LavenderDreamTheme.tokens,
    SunsetGlowTheme.id    => SunsetGlowTheme.tokens,
    _                     => MidnightPurpleTheme.tokens,
  };

  static ThemeData build(UsyncThemeData tokens) {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: GoogleFonts.inter().fontFamily,
      scaffoldBackgroundColor: tokens.bg1,
      extensions: [tokens],
      colorScheme: ColorScheme.dark(
        primary: tokens.primary,
        secondary: tokens.secondary,
        surface: tokens.bg2,
        onPrimary: AppColors.textPrimary,
        onSecondary: AppColors.textPrimary,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
      ),
      textTheme: const TextTheme(
        displayLarge:  AppTextStyles.h1,
        displayMedium: AppTextStyles.h2,
        displaySmall:  AppTextStyles.h3,
        headlineMedium:AppTextStyles.h4,
        bodyLarge:     AppTextStyles.bodyLarge,
        bodyMedium:    AppTextStyles.body,
        bodySmall:     AppTextStyles.labelSmall,
        labelLarge:    AppTextStyles.button,
        labelSmall:    AppTextStyles.labelCaps,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.glass,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.primary.withValues(alpha: 0.5)),
        ),
        hintStyle: const TextStyle(color: AppColors.textDim),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: AppTextStyles.button,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }
}
