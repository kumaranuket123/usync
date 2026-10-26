import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/animations/float_animation.dart';
import '../../../shared/widgets/heartbeat_visualizer.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/mood_chip.dart';
import '../../../shared/widgets/partner_orb.dart';
import '../../../../core/di/injection.dart';
import '../bloc/home_bloc.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<HomeBloc>()..add(HomeStarted()),
      child: const _HomeBody(),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (context, state) {
        if (state is HomeLoading) {
          return const Scaffold(
            backgroundColor: AppColors.bg1,
            body: Center(child: LoadingDots()),
          );
        }

        if (state is HomeError) {
          return Scaffold(
            backgroundColor: AppColors.bg1,
            body: Center(child: Text(state.message, style: AppTextStyles.bodyMuted)),
          );
        }

        final s = state is HomeLoaded ? state : null;
        final ownName      = s?.user.username        ?? '…';
        final ownEmoji     = s?.user.avatarEmoji     ?? '';
        final partnerEmoji = s?.partner.avatarEmoji  ?? '🌙';
        final partnerName  = s?.partner.username     ?? 'Your partner';
        final partnerMood  = s?.partnerMood;
        final moodEmoji    = partnerMood?.emoji;
        final moodText     = partnerMood == null ? '"Here with you…"' : '"${partnerMood.label}"';
        final isOnline     = s?.isOnline             ?? false;
        final recentMoods  = s?.recentMoods          ?? [];

        return Scaffold(
          backgroundColor: AppColors.bg1,
          body: Stack(
            children: [
              // Ambient glow blobs
              Positioned(
                top: -120, right: -100,
                child: Container(
                  width: 320, height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [AppColors.pink.withValues(alpha: 0.15), Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 80, left: -80,
                child: Container(
                  width: 280, height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [AppColors.purple.withValues(alpha: 0.15), Colors.transparent],
                    ),
                  ),
                ),
              ),

              // Floating emoji reactions
              ...{
                'emoji': '💖', 'x': 40.0,  'delay': 0,   'dur': 5000,
              }.let((_) => [
                _FloatEmoji('💖', x: 40,  delay: 0,    dur: 5000),
                _FloatEmoji('✨', x: 80,  delay: 2000, dur: 7000),
                _FloatEmoji('🌸', x: 310, delay: 1000, dur: 6000),
                _FloatEmoji('💜', x: 350, delay: 3000, dur: 8000),
              ]),

              SafeArea(
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Good evening,', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                              Text('$ownName $ownEmoji', style: AppTextStyles.h3.copyWith(fontSize: 20)),
                            ],
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => context.push(RouteNames.notifications),
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.glass,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.glassBorder),
                              ),
                              child: const Center(child: Text('🔔', style: TextStyle(fontSize: 20))),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Partner orb section
                    PartnerOrb(avatarEmoji: partnerEmoji, isOnline: isOnline),
                    Text(partnerName, style: AppTextStyles.partnerName),
                    const SizedBox(height: 6),
                    // Emoji above the words.
                    if (moodEmoji != null) ...[
                      Text(moodEmoji, style: const TextStyle(fontSize: 30)),
                      const SizedBox(height: 2),
                    ],
                    Text(moodText, style: AppTextStyles.moodText, textAlign: TextAlign.center),

                    const SizedBox(height: 12),
                    const HeartbeatVisualizer(),

                    const SizedBox(height: 10),

                    // Quick actions
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ActionPill('👆', 'Touch',  () => context.push(RouteNames.touchSync)),
                          _ActionPill('📍', 'Location', () => context.push(RouteNames.location)),
                          _ActionPill('💭', 'Mood',   () => context.push(RouteNames.mood)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Mood strip
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('RECENT MOODS', style: AppTextStyles.labelCaps),
                          const SizedBox(height: 10),
                          if (recentMoods.isEmpty)
                            Text('No moods shared yet', style: AppTextStyles.bodyMuted)
                          else
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ...recentMoods.map((m) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: MoodChip(emoji: m.emoji, label: m.label),
                                  )),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill(this.icon, this.label, this.onTap);
  final String icon, label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _FloatEmoji extends StatelessWidget {
  const _FloatEmoji(this.emoji, {required this.x, required this.delay, required this.dur});
  final String emoji;
  final double x;
  final int    delay, dur;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left:   x,
      bottom: 200,
      child: FloatAnimation(
        duration: Duration(milliseconds: dur),
        delay:    Duration(milliseconds: delay),
        child:    Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

extension<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
