import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/memory.dart';

Future<bool> confirmDeleteMemory(BuildContext context, Memory memory) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.bg2,
      title: const Text('Delete this moment?', style: TextStyle(color: Colors.white)),
      content: Text('"${memory.title}" will be removed for both of you.', style: AppTextStyles.bodyMuted),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete', style: TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );
  return ok == true;
}
