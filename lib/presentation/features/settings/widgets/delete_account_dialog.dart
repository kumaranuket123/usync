import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../auth/bloc/auth_bloc.dart';

/// Deleting the account cannot be undone, so the person has to type DELETE.
/// Used from Settings and from the pairing screens (for people who are signed in
/// but not paired yet).
Future<void> confirmAndDeleteAccount(BuildContext context) async {
  final auth = context.read<AuthBloc>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const DeleteAccountDialog(),
  );
  if (ok == true) auth.add(const DeleteAccountRequested());
}

/// Pops `true` once the person has typed DELETE and pressed Delete, `false` on Cancel.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});
  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _ctrl.text.trim().toUpperCase() == 'DELETE';
    return AlertDialog(
      backgroundColor: AppColors.bg2,
      title: const Text('Delete your account?', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently deletes your account and everything you shared with your partner: moods, memories, timeline, canvas, bucket list and question answers. If you are paired, your partner is disconnected. This cannot be undone.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 16),
            Text('Type DELETE to confirm', style: AppTextStyles.labelSmall),
            const SizedBox(height: 6),
            TextField(
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        TextButton(
          onPressed: confirmed ? () => Navigator.pop(context, true) : null,
          child: Text('Delete', style: TextStyle(color: confirmed ? const Color(0xFFFF5050) : AppColors.textDim)),
        ),
      ],
    );
  }
}
