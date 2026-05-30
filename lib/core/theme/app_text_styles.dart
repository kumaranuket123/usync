import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTextStyles {
  static const String? _font = null; // inherits from ThemeData.fontFamily (Inter via google_fonts)

  // ── Display ───────────────────────────────────────────────────
  static const TextStyle logoLarge = TextStyle(
    fontFamily: _font, fontSize: 46, fontWeight: FontWeight.w800,
    letterSpacing: 10, color: AppColors.textPrimary,
  );
  static const TextStyle logoSmall = TextStyle(
    fontFamily: _font, fontSize: 22, fontWeight: FontWeight.w800,
    letterSpacing: 4, color: AppColors.textPrimary,
  );

  // ── Headings ──────────────────────────────────────────────────
  static const TextStyle h1 = TextStyle(
    fontFamily: _font, fontSize: 30, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary, height: 1.25,
  );
  static const TextStyle h2 = TextStyle(
    fontFamily: _font, fontSize: 26, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  static const TextStyle h3 = TextStyle(
    fontFamily: _font, fontSize: 22, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  static const TextStyle h4 = TextStyle(
    fontFamily: _font, fontSize: 18, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  // ── Body ──────────────────────────────────────────────────────
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w400,
    color: AppColors.textPrimary, height: 1.6,
  );
  static const TextStyle body = TextStyle(
    fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w400,
    color: AppColors.textPrimary, height: 1.65,
  );
  static const TextStyle bodyMuted = TextStyle(
    fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w400,
    color: AppColors.textMuted, height: 1.65,
  );

  // ── Labels ────────────────────────────────────────────────────
  static const TextStyle labelCaps = TextStyle(
    fontFamily: _font, fontSize: 11, fontWeight: FontWeight.w600,
    color: AppColors.textMuted, letterSpacing: 1.5,
  );
  static const TextStyle labelSmall = TextStyle(
    fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );
  static const TextStyle label = TextStyle(
    fontFamily: _font, fontSize: 13, fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );

  // ── Action ────────────────────────────────────────────────────
  static const TextStyle button = TextStyle(
    fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w600,
    color: AppColors.textPrimary, letterSpacing: 0.5,
  );
  static const TextStyle link = TextStyle(
    fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w600,
    color: Color(0xFFFF6EC7),
  );

  // ── Partner / Mood ────────────────────────────────────────────
  static const TextStyle partnerName = TextStyle(
    fontFamily: _font, fontSize: 22, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  static const TextStyle moodText = TextStyle(
    fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w400,
    color: Color(0xFFFF6EC7), fontStyle: FontStyle.italic,
  );

  // ── Code ──────────────────────────────────────────────────────
  static const TextStyle inviteCode = TextStyle(
    fontFamily: _font, fontSize: 52, fontWeight: FontWeight.w800,
    letterSpacing: 14, color: AppColors.textPrimary,
  );
}
