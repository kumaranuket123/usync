import 'package:flutter/material.dart';

/// Custom theme tokens carried as a [ThemeExtension].
/// Access via: `Theme.of(context).extension<UsyncThemeData>()!`
class UsyncThemeData extends ThemeExtension<UsyncThemeData> {
  const UsyncThemeData({
    required this.primary,
    required this.primarySoft,
    required this.secondary,
    required this.bg1,
    required this.bg2,
    required this.bg3,
    required this.glass,
    required this.glassBorder,
    required this.textPrimary,
    required this.textMuted,
    required this.bgGradient,
    required this.primaryGradient,
    required this.gradientTextColors,
    required this.primaryGlow,
    required this.cardGlow,
    required this.orbGlow,
  });

  final Color primary;
  final Color primarySoft;
  final Color secondary;
  final Color bg1;
  final Color bg2;
  final Color bg3;
  final Color glass;
  final Color glassBorder;
  final Color textPrimary;
  final Color textMuted;
  final LinearGradient bgGradient;
  final LinearGradient primaryGradient;
  final List<Color> gradientTextColors;
  final List<BoxShadow> primaryGlow;
  final List<BoxShadow> cardGlow;
  final List<BoxShadow> orbGlow;

  @override
  UsyncThemeData copyWith({
    Color? primary,
    Color? primarySoft,
    Color? secondary,
    Color? bg1,
    Color? bg2,
    Color? bg3,
    Color? glass,
    Color? glassBorder,
    Color? textPrimary,
    Color? textMuted,
    LinearGradient? bgGradient,
    LinearGradient? primaryGradient,
    List<Color>? gradientTextColors,
    List<BoxShadow>? primaryGlow,
    List<BoxShadow>? cardGlow,
    List<BoxShadow>? orbGlow,
  }) {
    return UsyncThemeData(
      primary: primary ?? this.primary,
      primarySoft: primarySoft ?? this.primarySoft,
      secondary: secondary ?? this.secondary,
      bg1: bg1 ?? this.bg1,
      bg2: bg2 ?? this.bg2,
      bg3: bg3 ?? this.bg3,
      glass: glass ?? this.glass,
      glassBorder: glassBorder ?? this.glassBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      bgGradient: bgGradient ?? this.bgGradient,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      gradientTextColors: gradientTextColors ?? this.gradientTextColors,
      primaryGlow: primaryGlow ?? this.primaryGlow,
      cardGlow: cardGlow ?? this.cardGlow,
      orbGlow: orbGlow ?? this.orbGlow,
    );
  }

  @override
  UsyncThemeData lerp(ThemeExtension<UsyncThemeData>? other, double t) {
    if (other is! UsyncThemeData) return this;
    return UsyncThemeData(
      primary: Color.lerp(primary, other.primary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      bg1: Color.lerp(bg1, other.bg1, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      bg3: Color.lerp(bg3, other.bg3, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      bgGradient: LinearGradient.lerp(bgGradient, other.bgGradient, t)!,
      primaryGradient: LinearGradient.lerp(primaryGradient, other.primaryGradient, t)!,
      gradientTextColors: other.gradientTextColors,
      primaryGlow: other.primaryGlow,
      cardGlow: other.cardGlow,
      orbGlow: other.orbGlow,
    );
  }
}
