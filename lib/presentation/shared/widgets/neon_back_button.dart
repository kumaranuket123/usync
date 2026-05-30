import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';

class NeonBackButton extends StatelessWidget {
  const NeonBackButton({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      },
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color:        AppColors.glass,
          shape:        BoxShape.circle,
          border:       Border.all(color: AppColors.glassBorder),
        ),
        child: const Center(
          child: Text('‹', style: TextStyle(color: Colors.white, fontSize: 22, height: 1)),
        ),
      ),
    );
  }
}
