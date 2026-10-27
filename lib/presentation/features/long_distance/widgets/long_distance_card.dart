import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/geo_util.dart';
import '../../../shared/widgets/glow_button.dart';
import '../bloc/long_distance_bloc.dart';
import '../../../../core/utils/app_snack_bar.dart';

/// Home card for long-distance couples: how far apart you are and when you meet
/// next. Takes no space for couples who live together.
class LongDistanceCard extends StatelessWidget {
  const LongDistanceCard({super.key, required this.coupleId, required this.userId, required this.partnerId});
  final String coupleId, userId, partnerId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<LongDistanceBloc>()
        ..add(LongDistanceStarted(coupleId: coupleId, userId: userId, partnerId: partnerId)),
      child: BlocConsumer<LongDistanceBloc, LongDistanceState>(
        listenWhen: (a, b) => b.error != null && a.error != b.error,
        listener: (context, s) =>
            ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: Text(s.error!))),
        builder: (context, s) {
          if (!s.visible) return const SizedBox.shrink();
          final days = s.daysUntilMeet(DateTime.now());
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: GestureDetector(
              onTap: () => _edit(context, s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.glass,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  children: [
                    const Text('✈️', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_label(s, days), style: AppTextStyles.body.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Text('›', style: TextStyle(color: AppColors.textDim, fontSize: 18)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String _label(LongDistanceState s, int? days) {
    final apart = s.distanceMetres == null ? null : '${GeoUtil.formatDistance(s.distanceMetres!)} apart';
    final meet = switch (days) {
      null => 'Set our next meet',
      0    => 'We meet today 🎉',
      1    => 'We meet tomorrow',
      _    => 'Meet in $days days',
    };
    return apart == null ? meet : '$apart  ·  $meet';
  }

  Future<void> _edit(BuildContext context, LongDistanceState s) async {
    final bloc = context.read<LongDistanceBloc>();
    final action = await showModalBottomSheet<_MeetAction>(
      context: context,
      backgroundColor: AppColors.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _MeetSheet(hasDate: s.daysUntilMeet(DateTime.now()) != null),
    );
    if (action == null || !context.mounted) return;
    if (action == _MeetAction.clear) {
      bloc.add(NextMeetChosen(null));
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: s.nextMeetOn != null && !s.nextMeetOn!.isBefore(today) ? s.nextMeetOn! : today,
      firstDate: today,
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) bloc.add(NextMeetChosen(picked));
  }
}

enum _MeetAction { choose, clear }

class _MeetSheet extends StatelessWidget {
  const _MeetSheet({required this.hasDate});
  final bool hasDate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Next time we meet ✈️', style: AppTextStyles.h3),
            const SizedBox(height: 4),
            Text('Shared with your partner, so you both count down together.', style: AppTextStyles.labelSmall),
            const SizedBox(height: 18),
            GlowButton(label: hasDate ? 'Change date' : 'Choose date', onTap: () => Navigator.pop(context, _MeetAction.choose)),
            if (hasDate)
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, _MeetAction.clear),
                  child: Text('Remove date', style: AppTextStyles.link),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
