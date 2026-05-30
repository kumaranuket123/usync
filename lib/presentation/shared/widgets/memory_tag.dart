import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../domain/entities/memory.dart';

class MemoryTag extends StatelessWidget {
  const MemoryTag({super.key, required this.type});
  final MemoryType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        type.tagBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        type.tagLabel,
        style: AppTextStyles.labelSmall.copyWith(
          color:      type.tagColor,
          fontWeight: FontWeight.w600,
          fontSize:   11,
        ),
      ),
    );
  }
}
