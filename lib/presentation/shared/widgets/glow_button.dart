import 'package:flutter/material.dart';

import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import 'loading_dots.dart';

class GlowButton extends StatelessWidget {
  const GlowButton({
    super.key,
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.gradient,
    this.height    = 56.0,
    this.radius    = 16.0,
    this.shadows,
  });

  final String             label;
  final VoidCallback?      onTap;
  final bool               isLoading;
  final LinearGradient?    gradient;
  final double             height;
  final double             radius;
  final List<BoxShadow>?   shadows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grad  = gradient ??
        LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.secondary]);

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: height,
        decoration: BoxDecoration(
          gradient:     grad,
          borderRadius: BorderRadius.circular(radius),
          boxShadow:    shadows ?? AppShadows.buttonGlow,
        ),
        child: Center(
          child: isLoading
              ? const LoadingDots()
              : Text(label, style: AppTextStyles.button),
        ),
      ),
    );
  }
}
