import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Bottom-nav tab: things the couple can do together.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
          children: [
            Text('Activity', style: AppTextStyles.h2),
            Text('Things to do together', style: AppTextStyles.label),
            const SizedBox(height: 20),
            _ActivityCard(
              emoji: '🎮',
              color: const Color(0x1FFFD700),
              title: 'Couple games',
              subtitle: 'Play something together',
              onTap: () => context.push(RouteNames.games),
            ),
            _ActivityCard(
              emoji: '🎯',
              color: const Color(0x1F00D4FF),
              title: 'Bucket list',
              subtitle: 'Things we want to do together',
              onTap: () => context.push(RouteNames.bucketList),
            ),
            _ActivityCard(
              emoji: '🕰️',
              color: const Color(0x1FFF2D78),
              title: 'Relationship timeline',
              subtitle: 'View your shared journey',
              onTap: () => context.push(RouteNames.timeline),
            ),
            const SizedBox(height: 4),
            const _ComingSoonBanner(),
          ],
        ),
      ),
    );
  }
}

/// Tells people more is on the way, so they come back to this tab.
class _ComingSoonBanner extends StatelessWidget {
  const _ComingSoonBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
          colors: [scheme.primary.withValues(alpha: 0.16), scheme.secondary.withValues(alpha: 0.10)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          const Text('✨', style: TextStyle(fontSize: 28)),
          const SizedBox(height: 8),
          Text('More coming soon', style: AppTextStyles.h4),
          const SizedBox(height: 4),
          Text(
            'We are building more ways for the two of you to spend time together. Check back soon.',
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSmall.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.emoji, required this.color, required this.title, required this.subtitle, required this.onTap});

  final String       emoji, title, subtitle;
  final Color        color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.h4),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.label),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
