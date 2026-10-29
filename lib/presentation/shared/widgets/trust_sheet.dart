import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_names.dart';
import '../../../core/constants/trust_copy.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/privacy_policy.dart';

/// "How we protect you": what is encrypted, what is still visible and who handles data.
/// [showSecurityLink] adds a shortcut to Profile → Security (only for signed-in people).
Future<void> showTrustSheet(BuildContext context, {bool showSecurityLink = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.bg2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => _TrustSheet(
      onSecurity: showSecurityLink
          ? () {
              Navigator.of(sheetContext).pop();
              context.push(RouteNames.security);
            }
          : null,
    ),
  );
}

class _TrustSheet extends StatelessWidget {
  const _TrustSheet({this.onSecurity});
  final VoidCallback? onSecurity;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.glassMid, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text('🔒 ${TrustCopy.headline}', style: AppTextStyles.h2.copyWith(fontSize: 22)),
          const SizedBox(height: 8),
          Text(TrustCopy.summary, style: AppTextStyles.bodyMuted),
          const SizedBox(height: 20),
          const _Block('Only the two of you can read', TrustCopy.encrypted),
          const _Block('What we can still see', TrustCopy.stillVisible),
          const _Block('Services we rely on', TrustCopy.services),
          Text(TrustCopy.promise, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (onSecurity != null)
                FilledButton.icon(
                  onPressed: onSecurity,
                  icon: const Icon(Icons.key_rounded, size: 18),
                  label: const Text('Check my security code'),
                ),
              OutlinedButton(
                onPressed: () => openPrivacyPolicy(context),
                child: const Text('Privacy Policy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block(this.title, this.lines);
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: AppTextStyles.labelCaps),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(color: AppColors.textMuted)),
                  Expanded(child: Text(line, style: AppTextStyles.bodyMuted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
