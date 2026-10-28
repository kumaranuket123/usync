import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/encryption_state.dart';
import '../../../shared/widgets/glass_input.dart';
import '../../../shared/widgets/glow_button.dart';

/// The Security page content, without any loading or navigation so it is easy to test.
class SecurityView extends StatefulWidget {
  const SecurityView({
    super.key,
    required this.encryption,
    required this.partnerName,
    required this.busy,
    required this.onVerify,
    required this.onApprove,
    required this.onSetUpRecovery,
    required this.onRestore,
    required this.onReset,
  });

  final EncryptionState encryption;
  final String          partnerName;
  final bool            busy;
  final VoidCallback    onVerify, onApprove, onSetUpRecovery, onReset;
  final ValueChanged<String> onRestore;

  @override
  State<SecurityView> createState() => _SecurityViewState();
}

class _SecurityViewState extends State<SecurityView> {
  final _phrase = TextEditingController();

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: const Text('Reset your keys?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This makes new keys for you. Your old recovery phrase stops working, and ${widget.partnerName} has to approve '
          'your new keys before you can read your shared history again. If neither of you still has the old keys, that history is lost.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Reset', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) widget.onReset();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.encryption;
    final name = widget.partnerName;
    final needsRestore = e.phase == EncryptionPhase.needsRestore;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusCard(phase: e.phase, name: name),
          if (e.securityCode != null) ...[
            const SizedBox(height: 14),
            _CodeCard(
              code: e.securityCode!,
              name: name,
              verified: e.partnerVerified && e.phase != EncryptionPhase.needsVerification,
              changed: e.phase == EncryptionPhase.partnerKeyChanged,
              busy: widget.busy,
              onVerify: widget.onVerify,
              onApprove: widget.onApprove,
            ),
          ],
          if (needsRestore) ...[
            const SizedBox(height: 14),
            _Card(
              title: 'Restore your keys',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Type the 12 words you saved when you set up your recovery phrase.', style: AppTextStyles.bodyMuted),
                  const SizedBox(height: 12),
                  GlassInput(hint: 'word1 word2 word3 …', controller: _phrase, keyboardType: TextInputType.multiline),
                  const SizedBox(height: 12),
                  GlowButton(
                    label: widget.busy ? 'Restoring…' : 'Restore',
                    onTap: widget.busy ? null : () => widget.onRestore(_phrase.text),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: widget.busy ? null : _confirmReset,
                      child: Text('I lost my phrase', style: AppTextStyles.link),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            _Card(
              title: 'Recovery phrase',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.recoverySetUp
                        ? 'Saved ✓. You can use it to get your keys back on a new phone.'
                        : 'Not set up. Without it, a lost or reset phone could lose your encrypted history. Nobody can recover it for you, not even the developer.',
                    style: AppTextStyles.bodyMuted,
                  ),
                  const SizedBox(height: 12),
                  GlowButton(
                    label: e.recoverySetUp ? 'Make a new phrase' : 'Set up recovery phrase',
                    onTap: widget.busy ? null : widget.onSetUpRecovery,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: widget.busy ? null : _confirmReset,
                child: Text('Reset my keys', style: AppTextStyles.labelSmall.copyWith(decoration: TextDecoration.underline)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.title});
  final Widget  child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!.toUpperCase(), style: AppTextStyles.labelCaps),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.phase, required this.name});
  final EncryptionPhase phase;
  final String          name;

  @override
  Widget build(BuildContext context) {
    final (emoji, title, text) = switch (phase) {
      EncryptionPhase.ready             => ('🔐', 'Your keys are ready', 'End-to-end encryption keys are set up between you and $name, and you compared the security code. Your content will be encrypted with them in an upcoming update.'),
      EncryptionPhase.needsVerification => ('🔎', 'Compare your security code', 'Nothing is shared until you and $name have compared the code below, on a call or in person. It makes sure nobody is listening in between you.'),
      EncryptionPhase.noCouple          => ('🔐', 'Your keys are ready', 'Pair with your partner and the two of you will share a key that only you hold.'),
      EncryptionPhase.waitingForPartner => ('⏳', 'Waiting for $name', '$name needs to open the latest version of Usync to finish setting up.'),
      EncryptionPhase.waitingForKey     => ('⏳', 'Waiting for $name\'s phone', 'Their phone will share your couple\'s key with this one. It happens when they open the app.'),
      EncryptionPhase.needsApproval     => ('🔒', 'Waiting for $name to approve', 'Your keys changed. $name has to compare the security code and approve before you can read your shared history.'),
      EncryptionPhase.partnerKeyChanged => ('⚠️', '$name\'s security code changed', 'This happens when they set up a new phone or reset their keys. Compare the code below with them, then approve.'),
      EncryptionPhase.needsRestore      => ('🔑', 'Restore your keys', 'This account already has keys, but not on this phone.'),
      EncryptionPhase.unknown           => ('⏳', 'Checking your keys…', 'This needs a connection.'),
    };
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.h3),
                const SizedBox(height: 4),
                Text(text, style: AppTextStyles.bodyMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.code,
    required this.name,
    required this.verified,
    required this.changed,
    required this.busy,
    required this.onVerify,
    required this.onApprove,
  });

  final String       code, name;
  final bool         verified, changed, busy;
  final VoidCallback onVerify, onApprove;

  @override
  Widget build(BuildContext context) {
    final groups = code.split(' ');
    return _Card(
      title: 'Security code',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var row = 0; row < groups.length; row += 4)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                groups.skip(row).take(4).join('   '),
                style: AppTextStyles.h3.copyWith(letterSpacing: 1.5, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Read this to $name on a call or in person. If both of you see the same numbers, nobody can be listening in between you.',
            style: AppTextStyles.labelSmall.copyWith(height: 1.5),
          ),
          const SizedBox(height: 12),
          if (changed)
            GlowButton(label: busy ? 'Approving…' : 'They match: approve', onTap: busy ? null : onApprove)
          else if (verified)
            Text('✓ Verified with $name', style: AppTextStyles.body.copyWith(color: AppColors.pinkLight))
          else
            GlowButton(label: busy ? 'Saving…' : 'They match', onTap: busy ? null : onVerify),
        ],
      ),
    );
  }
}
