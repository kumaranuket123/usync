import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/mood_insights_bloc.dart';
import '../widgets/mood_insights_view.dart';

class MoodInsightsScreen extends StatelessWidget {
  const MoodInsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    final open = InsightsOpened(coupleId: user?.coupleId ?? '', userId: user?.id ?? '');
    return BlocProvider(
      create: (_) => GetIt.I<MoodInsightsBloc>()..add(open),
      child: Scaffold(
        backgroundColor: AppColors.bg1,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 12),
                child: Row(
                  children: [
                    const NeonBackButton(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Mood insights', style: AppTextStyles.h2.copyWith(fontSize: 22), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('How in sync you\'ve been this week', style: AppTextStyles.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: BlocBuilder<MoodInsightsBloc, MoodInsightsState>(
                  builder: (context, state) => switch (state) {
                    InsightsLoading() => const Center(child: LoadingDots()),
                    InsightsReady(:final insights, :final partnerName) =>
                      MoodInsightsView(insights: insights, partnerName: partnerName),
                    InsightsError(:final message) => Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(message, style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              GlowButton(label: 'Try again', onTap: () => context.read<MoodInsightsBloc>().add(open)),
                            ],
                          ),
                        ),
                      ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
