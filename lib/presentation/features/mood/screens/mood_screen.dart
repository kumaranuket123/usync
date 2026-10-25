import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/push_notification_service.dart' show rootMessengerKey;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/mood.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../shared/widgets/glass_input.dart';
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
          if (state is MoodSentSuccess) {
            if (state.queued) {
              // The screen closes, so the message goes on the app-level messenger.
              rootMessengerKey.currentState?.showSnackBar(const SnackBar(
                content: Text('You are offline. Your mood will be sent when you are back online.'),
              ));
            }
            context.pop();
          }
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
    final uid  = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final user = await GetIt.I<IAuthRepository>().getCurrentUser();
    if (user?.coupleId == null || !mounted) return;
    context.read<MoodBloc>().add(
      MoodScreenOpened(coupleId: user!.coupleId!, userId: uid),
    );
  }

  Future<void> _addCustom() async {
    final bloc = context.read<MoodBloc>();
    final custom = await showModalBottomSheet<CustomMood>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _CustomMoodSheet(),
    );
    if (custom != null) bloc.add(CustomMoodAdded(custom));
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
                  final ready    = state is MoodReady ? state : null;
                  final selected = ready?.selectedMood;
                  final custom   = ready?.selectedCustom;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      alignment: WrapAlignment.center,
                      children: [
                        ..._moods.map((entry) => MoodBubble(
                              emoji:        entry.type.emoji,
                              label:        entry.type.label,
                              isSelected:   selected == entry.type,
                              animDuration: entry.animDuration,
                              animDelay:    entry.animDelay,
                              onTap: () => context
                                  .read<MoodBloc>()
                                  .add(MoodSelected(entry.type)),
                            )),
                        // The user's own moods from before.
                        ...?ready?.customMoods.map((c) => MoodBubble(
                              emoji:      c.emoji,
                              label:      c.label,
                              isSelected: selected == MoodType.custom && custom == c,
                              onTap: () => context.read<MoodBloc>().add(CustomMoodSelected(c)),
                            )),
                        MoodBubble(
                          emoji:      '＋',
                          label:      'Custom',
                          isSelected: false,
                          animDuration: const Duration(milliseconds: 4600),
                          onTap: _addCustom,
                        ),
                      ],
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

/// Lets the user make up a mood: a few words and an emoji.
class _CustomMoodSheet extends StatefulWidget {
  const _CustomMoodSheet();
  @override
  State<_CustomMoodSheet> createState() => _CustomMoodSheetState();
}

class _CustomMoodSheetState extends State<_CustomMoodSheet> {
  static const _emojis = [
    '😊', '🥰', '😎', '🤗', '😌', '🥱', '🤒', '😢',
    '😤', '🤩', '🍕', '☕', '🎧', '🏃', '✈️', '🌧️',
  ];

  final _label = TextEditingController();
  String _emoji = _emojis.first;

  @override
  void initState() {
    super.initState();
    _label.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _save() {
    final label = _label.text.trim();
    if (label.isEmpty) return;
    Navigator.pop(context, CustomMood(label: label, emoji: _emoji));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your own mood', style: AppTextStyles.h3.copyWith(color: Colors.white)),
            const SizedBox(height: 16),
            GlassInput(label: 'HOW ARE YOU FEELING', hint: 'Craving pizza', controller: _label, maxLength: 40),
            const SizedBox(height: 12),
            const Text('EMOJI', style: AppTextStyles.labelCaps),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _emojis)
                  GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: e == _emoji ? AppColors.pink.withValues(alpha: 0.2) : AppColors.glass,
                        border: Border.all(color: e == _emoji ? AppColors.pink : AppColors.glassBorder),
                      ),
                      child: Center(child: Text(e, style: const TextStyle(fontSize: 20))),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            GlowButton(
              label: 'Use this mood',
              onTap: _label.text.trim().isEmpty ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
