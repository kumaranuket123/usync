import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── Brand ─────────────────────────────────────────────────────
  static const Color pink       = Color(0xFFFF2D78);
  static const Color pinkLight  = Color(0xFFFF6EC7);
  static const Color purple     = Color(0xFF9D4EDD);
  static const Color purpleDeep = Color(0xFF4A0E8F);
  static const Color lavender   = Color(0xFFC77DFF);
  static const Color cyan       = Color(0xFF00D4FF);
  static const Color cyanSoft   = Color(0xFF7FEFFF);
  static const Color gold       = Color(0xFFFFD700);

  // ── Backgrounds ───────────────────────────────────────────────
  static const Color bg1       = Color(0xFF0D0D2B); // darkest
  static const Color bg2       = Color(0xFF1A0533);
  static const Color bg3       = Color(0xFF0A1628);
  static const Color midnight  = Color(0xFF0A0A1F);

  // ── Glass surfaces ────────────────────────────────────────────
  static const Color glass       = Color(0x0DFFFFFF); // 5% white
  static const Color glassBorder = Color(0x14FFFFFF); // 8% white
  static const Color glassMid    = Color(0x1AFFFFFF); // 10% white

  // ── Text ──────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xE6FFFFFF); // 90% white
  static const Color textMuted   = Color(0x73FFFFFF); // 45% white
  static const Color textDim     = Color(0x4DFFFFFF); // 30% white

  // ── Semantic ──────────────────────────────────────────────────
  static const Color online  = Color(0xFF00E676);
  static const Color offline = Color(0xFF555577);
  static const Color error   = Color(0xFFFF5252);
}
