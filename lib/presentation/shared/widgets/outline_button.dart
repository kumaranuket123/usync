import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class UsyncOutlineButton extends StatelessWidget {
  const UsyncOutlineButton({
    super.key,
    required this.label,
    required this.onTap,
    this.textColor,
    this.borderColor,
  });

  final String     label;
  final VoidCallback onTap;
  final Color?     textColor;
  final Color?     borderColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color:        AppColors.glass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor ?? AppColors.glassBorder),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.button.copyWith(
              color: textColor ?? AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
