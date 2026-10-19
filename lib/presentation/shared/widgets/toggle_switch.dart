import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class ToggleSwitch extends StatelessWidget {
  const ToggleSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 46, height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: value ? null : AppColors.glassMid,
          gradient: value
              ? LinearGradient(colors: [primary, Theme.of(context).colorScheme.secondary])
              : null,
          boxShadow: value
              ? [BoxShadow(color: primary.withValues(alpha: 0.4), blurRadius: 12)]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 300),
          curve:    Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20, height: 20,
            margin: const EdgeInsets.all(3),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
