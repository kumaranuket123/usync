import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../domain/entities/encryption_state.dart';
import '../../../domain/repositories/i_encryption_repository.dart';
import 'trust_sheet.dart';

/// What the badge says for a phase, and whether tapping it needs the person to act.
class EncryptionBadgeInfo {
  const EncryptionBadgeInfo(this.emoji, this.label, this.color, {this.needsAction = false});
  final String emoji;
  final String label;
  final Color  color;
  final bool   needsAction;
}

/// Nothing is claimed until the phone has really checked: [EncryptionPhase.unknown] shows no badge.
EncryptionBadgeInfo? encryptionBadgeFor(EncryptionPhase phase) => switch (phase) {
      EncryptionPhase.ready => const EncryptionBadgeInfo('🔒', 'End-to-end encrypted', AppColors.online),
      EncryptionPhase.needsVerification =>
        const EncryptionBadgeInfo('🔑', 'Compare your security code', AppColors.gold, needsAction: true),
      EncryptionPhase.waitingForPartner ||
      EncryptionPhase.noCouple ||
      EncryptionPhase.waitingForKey =>
        const EncryptionBadgeInfo('⏳', 'Securing your connection…', AppColors.cyan),
      EncryptionPhase.needsRestore ||
      EncryptionPhase.needsApproval ||
      EncryptionPhase.partnerKeyChanged =>
        const EncryptionBadgeInfo('⚠️', 'Action needed to stay secure', AppColors.gold, needsAction: true),
      EncryptionPhase.unknown => null,
    };

/// A small pill on Home that follows the real encryption state.
class EncryptionBadge extends StatefulWidget {
  const EncryptionBadge({super.key});

  @override
  State<EncryptionBadge> createState() => _EncryptionBadgeState();
}

class _EncryptionBadgeState extends State<EncryptionBadge> {
  late final IEncryptionRepository _repo = GetIt.I<IEncryptionRepository>();
  late EncryptionPhase _phase = _repo.current.phase;
  StreamSubscription<EncryptionState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _repo.changes.listen((s) {
      if (mounted && s.phase != _phase) setState(() => _phase = s.phase);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = encryptionBadgeFor(_phase);
    if (info == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => info.needsAction
          ? context.push(RouteNames.security)
          : showTrustSheet(context, showSecurityLink: true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: info.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: info.color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(info.emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(info.label,
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}
