import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/milestone.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../bloc/timeline_bloc.dart';

class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth     = context.read<AuthBloc>().state;
    final coupleId = auth is Authenticated ? (auth.user.coupleId ?? '') : '';
    return BlocProvider(
      create: (_) => GetIt.I<TimelineBloc>()..add(TimelineLoaded(coupleId)),
      child: const _TimelineBody(),
    );
  }
}

class _TimelineBody extends StatelessWidget {
  const _TimelineBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Row(
                children: [
                  const NeonBackButton(),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Our Journey', style: AppTextStyles.h2.copyWith(fontSize: 24)),
                      BlocBuilder<TimelineBloc, TimelineState>(
                        builder: (context, state) => Text(
                          state is TimelineReady
                              ? '${state.daysTogether} days together'
                              : '…',
                          style: AppTextStyles.label,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<TimelineBloc, TimelineState>(
                builder: (context, state) {
                  if (state is TimelineLoading) return const Center(child: LoadingDots());
                  if (state is TimelineReady) {
                    return _TimelineList(milestones: state.milestones);
                  }
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.milestones});
  final List<Milestone> milestones;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Gradient line
        Positioned(
          left: 43, top: 16, bottom: 40,
          child: Container(
            width: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end:   Alignment.bottomCenter,
                colors: [AppColors.pink, AppColors.purple, AppColors.cyan],
              ),
            ),
          ),
        ),
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
          itemCount: milestones.length,
          itemBuilder: (_, i) => _TimelineItem(milestone: milestones[i], index: i),
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.milestone, required this.index});
  final Milestone milestone;
  final int       index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dot
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bg1,
              border: Border.all(color: AppColors.pink.withOpacity(0.4), width: 1.5),
              boxShadow: [BoxShadow(color: AppColors.pink.withOpacity(0.3), blurRadius: 14)],
            ),
            child: Center(child: Text(milestone.type.emoji, style: const TextStyle(fontSize: 17))),
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GlassCard(
                borderRadius: 16,
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(milestone.title, style: AppTextStyles.label.copyWith(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                    if (milestone.note != null) ...[
                      const SizedBox(height: 4),
                      Text(milestone.note!, style: AppTextStyles.labelSmall.copyWith(height: 1.5)),
                    ],
                    const SizedBox(height: 5),
                    Text(milestone.occurredAt.formatted, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textDim)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _DateExt on DateTime {
  String get formatted {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[month - 1]} $day, $year';
  }
}
