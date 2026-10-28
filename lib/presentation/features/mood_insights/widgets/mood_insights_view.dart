import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/mood.dart';
import '../../../../domain/entities/mood_insights.dart';

/// The insights themselves, without any loading or navigation, so it is easy to test.
class MoodInsightsView extends StatelessWidget {
  const MoodInsightsView({super.key, required this.insights, required this.partnerName});

  final MoodInsights insights;
  final String       partnerName;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const _Empty();
    final total = insights.days.length;
    final n     = insights.inSyncDays;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('IN SYNC', style: AppTextStyles.labelCaps),
                const SizedBox(height: 6),
                Text('$n of the last $total days', style: AppTextStyles.h2),
                const SizedBox(height: 6),
                Text(
                  n == 0
                      ? 'No in-sync days yet. Share how you feel and see where you meet.'
                      : n == total
                          ? 'Every single day. You two are completely in tune 💞'
                          : 'On $n ${n == 1 ? 'day' : 'days'} you both felt alike 💞',
                  style: AppTextStyles.bodyMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [for (final d in insights.days) Expanded(child: _DayColumn(d))],
                ),
                const SizedBox(height: 10),
                Text(
                  'Top row: you   ·   Bottom row: $partnerName',
                  style: AppTextStyles.labelSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _TopMood(title: 'You shared most', mood: insights.myTop),
          const SizedBox(height: 8),
          _TopMood(title: '$partnerName shared most', mood: insights.partnerTop),
          const SizedBox(height: 16),
          Text(
            'Days follow UTC, so you and your partner are compared on the same day wherever you are. '
            'Moods feel alike when they are in the same group: warm (happy, thinking of you, missing you), '
            'calm (sleeping, relaxing) or busy.',
            style: AppTextStyles.labelSmall.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    // Scrolls instead of overflowing on a small phone or with large text.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💞', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text('Nothing to show yet', style: AppTextStyles.h3),
            const SizedBox(height: 6),
            Text(
              'Share a mood to start seeing insights. Once you both have, you will see how in sync you are.',
              style: AppTextStyles.bodyMuted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

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
      child: child,
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn(this.day);
  final MoodDay day;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(DateFormat.E().format(day.day).substring(0, 1), style: AppTextStyles.labelSmall),
        const SizedBox(height: 8),
        _Cell(day.mine?.emoji),
        const SizedBox(height: 6),
        _Cell(day.partner?.emoji),
        const SizedBox(height: 6),
        // Keeps its height on every day so the columns line up.
        Text(day.inSync ? '💞' : ' ', style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.emoji);
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34, height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: emoji == null ? Colors.transparent : AppColors.glass,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.glassBorder.withValues(alpha: emoji == null ? 0.4 : 1)),
      ),
      child: emoji == null
          ? Text('·', style: AppTextStyles.labelSmall)
          : FittedBox(child: Text(emoji!, style: const TextStyle(fontSize: 18))),
    );
  }
}

class _TopMood extends StatelessWidget {
  const _TopMood({required this.title, required this.mood});
  final String title;
  final Mood?  mood;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Text(mood?.emoji ?? '·', style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(mood?.label ?? 'No moods this week', style: AppTextStyles.body.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
