import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class LiveIndicator extends StatefulWidget {
  const LiveIndicator({super.key, required this.label, this.color, this.isActive = true});
  final String  label;
  final Color?  color;
  final bool    isActive;

  @override
  State<LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<LiveIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _scale = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = widget.isActive
        ? (widget.color ?? AppColors.cyan)
        : AppColors.offline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: _scale,
          child: Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color:     dotColor,
              shape:     BoxShape.circle,
              boxShadow: [BoxShadow(color: dotColor.withValues(alpha: 0.7), blurRadius: 6)],
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(widget.label, style: AppTextStyles.label.copyWith(color: dotColor.withValues(alpha: 0.85))),
      ],
    );
  }
}
