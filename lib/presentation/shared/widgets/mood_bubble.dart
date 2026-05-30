import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../domain/entities/mood.dart';
import 'glass_card.dart';

class MoodBubble extends StatefulWidget {
  const MoodBubble({
    super.key,
    required this.type,
    required this.isSelected,
    required this.onTap,
    this.animDuration  = const Duration(milliseconds: 3800),
    this.animDelay     = Duration.zero,
  });

  final MoodType  type;
  final bool      isSelected;
  final VoidCallback onTap;
  final Duration  animDuration;
  final Duration  animDelay;

  @override
  State<MoodBubble> createState() => _MoodBubbleState();
}

class _MoodBubbleState extends State<MoodBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _y;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.animDuration);
    _y    = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(widget.animDelay, () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _y.value),
        child: child,
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale:    widget.isSelected ? 1.12 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: GlassCard(
            borderRadius: 26,
            opacity:      widget.isSelected ? 0.0 : 0.045,
            borderColor:  widget.isSelected
                ? AppColors.pink.withOpacity(0.4)
                : AppColors.glassBorder,
            boxShadow: widget.isSelected
                ? [BoxShadow(color: AppColors.pink.withOpacity(0.30), blurRadius: 25)]
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.type.emoji, style: const TextStyle(fontSize: 38)),
                const SizedBox(height: 8),
                Text(
                  widget.type.label,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: widget.isSelected ? Colors.white : AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
