import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/mood.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/mood_bubble.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../bloc/mood_bloc.dart';

class MoodScreen extends StatelessWidget {
  const MoodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.I<MoodBloc>(),
      child: BlocListener<MoodBloc, MoodState>(
        listener: (context, state) {
          if (state is MoodSentSuccess) context.pop();
          if (state is MoodError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: const _MoodBody(),
      ),
    );
  }
}

// ── Entry model ─────────────────────────────────────────────────
class _MoodEntry {
  const _MoodEntry(this.type, this.animDuration, this.animDelay);
  final MoodType type;
  final Duration animDuration;
  final Duration animDelay;
}

// ── Body ────────────────────────────────────────────────────────
class _MoodBody extends StatefulWidget {
  const _MoodBody();
  @override
  State<_MoodBody> createState() => _MoodBodyState();
}

class _MoodBodyState extends State<_MoodBody> {
  static const _moods = [
    _MoodEntry(MoodType.happy,            Duration(milliseconds: 3200), Duration.zero),
    _MoodEntry(MoodType.thinkingAboutYou, Duration(milliseconds: 4000), Duration(milliseconds: 400)),
    _MoodEntry(MoodType.missingYou,       Duration(milliseconds: 3600), Duration(milliseconds: 800)),
    _MoodEntry(MoodType.sleeping,         Duration(milliseconds: 4400), Duration(milliseconds: 200)),
    _MoodEntry(MoodType.relaxing,         Duration(milliseconds: 3800), Duration(milliseconds: 600)),
    _MoodEntry(MoodType.busy,             Duration(milliseconds: 4200), Duration(milliseconds: 1000)),
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid  = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final user = await GetIt.I<IAuthRepository>().getCurrentUser();
    if (user?.coupleId == null || !mounted) return;
    context.read<MoodBloc>().add(
      MoodScreenOpened(coupleId: user!.coupleId!, userId: uid),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
              child: Row(
                children: [
                  const NeonBackButton(),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('How are you feeling?',
                          style: AppTextStyles.h2.copyWith(fontSize: 22)),
                      Text('Your partner will feel this',
                          style: AppTextStyles.label),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<MoodBloc, MoodState>(
                builder: (context, state) {
                  final selected =
                      state is MoodReady ? state.selectedMood : null;
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      alignment: WrapAlignment.center,
                      children: _moods.map((entry) {
                        return MoodBubble(
                          type:         entry.type,
                          isSelected:   selected == entry.type,
                          animDuration: entry.animDuration,
                          animDelay:    entry.animDelay,
                          onTap: () => context
                              .read<MoodBloc>()
                              .add(MoodSelected(entry.type)),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: BlocBuilder<MoodBloc, MoodState>(
                builder: (context, state) => GlowButton(
                  label:     'Send My Mood ✦',
                  isLoading: state is MoodReady && state.isSending,
                  onTap:     () => context.read<MoodBloc>().add(MoodSent()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
