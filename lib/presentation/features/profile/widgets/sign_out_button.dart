import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/outline_button.dart';

/// "Sign Out" with a confirmation; [onConfirmed] runs only if the person agrees.
class SignOutButton extends StatelessWidget {
  const SignOutButton({super.key, required this.onConfirmed});
  final VoidCallback onConfirmed;

  Future<void> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: const Text('Sign out?', style: TextStyle(color: Colors.white)),
        content: Text('You can sign back in any time.', style: AppTextStyles.bodyMuted),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out', style: TextStyle(color: Color(0xFFFF5050))),
          ),
        ],
      ),
    );
    if (ok == true) onConfirmed();
  }

  @override
  Widget build(BuildContext context) => UsyncOutlineButton(
        label: 'Sign Out',
        textColor:   const Color(0xB3FF5050),
        borderColor: const Color(0x33FF5050),
        onTap: () => _confirm(context),
      );
}
