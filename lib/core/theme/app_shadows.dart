import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppShadows {
  static List<BoxShadow> primaryGlow = [
    BoxShadow(color: AppColors.pink.withOpacity(0.45), blurRadius: 30),
    BoxShadow(color: AppColors.pink.withOpacity(0.20), blurRadius: 60),
  ];

  static List<BoxShadow> primaryGlowStrong = [
    BoxShadow(color: AppColors.pink.withOpacity(0.70), blurRadius: 50),
    BoxShadow(color: AppColors.purple.withOpacity(0.35), blurRadius: 100),
  ];

  static List<BoxShadow> cardGlow = [
    BoxShadow(color: AppColors.purple.withOpacity(0.15), blurRadius: 20),
  ];

  static List<BoxShadow> orbGlow = [
    BoxShadow(color: AppColors.pink.withOpacity(0.35), blurRadius: 50),
    BoxShadow(color: AppColors.purple.withOpacity(0.20), blurRadius: 100),
  ];

  static List<BoxShadow> cyanGlow = [
    BoxShadow(color: AppColors.cyan.withOpacity(0.50), blurRadius: 20),
    BoxShadow(color: AppColors.cyan.withOpacity(0.25), blurRadius: 40),
  ];

  static List<BoxShadow> buttonGlow = [
    BoxShadow(color: AppColors.pink.withOpacity(0.40), blurRadius: 30, offset: const Offset(0, 4)),
    BoxShadow(color: Colors.black.withOpacity(0.30), blurRadius: 20, offset: const Offset(0, 4)),
  ];
}
