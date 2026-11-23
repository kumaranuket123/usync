import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../long_distance/widgets/long_distance_card.dart';
import '../../../shared/animations/float_animation.dart';
import '../../../shared/widgets/heartbeat_visualizer.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/encryption_badge.dart';
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
        final unreadChat   = s?.unreadChat           ?? 0;

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
                // Scrolls when a large font or display size makes the content taller than the screen.
                child: SingleChildScrollView(
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

                    // Live encryption status; hidden until the phone has checked.
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 26),
                      child: Align(alignment: Alignment.centerLeft, child: EncryptionBadge()),
                    ),

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
                      // Wraps onto a second line when the pills do not fit in one row.
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ActionPill('👆', 'Touch',  () => context.push(RouteNames.touchSync)),
                          _ActionPill('📍', 'Location', () => context.push(RouteNames.location)),
                          _ActionPill('💭', 'Mood',   () => context.push(RouteNames.mood)),
                          _ActionPill('💬', 'Question', () => context.push(RouteNames.question)),
                          _ActionPill('💌', 'Chat', () => context.push(RouteNames.chat), badge: unreadChat),
                          _ActionPill('🎮', 'Games', () => context.push(RouteNames.games)),
                        ],
                      ),
                    ),

                    // Long-distance couples only; takes no space otherwise.
                    if (s != null)
                      LongDistanceCard(coupleId: s.couple.id, userId: s.user.id, partnerId: s.partner.id),

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
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill(this.icon, this.label, this.onTap, {this.badge = 0});
  final String icon, label;
  final VoidCallback onTap;
  /// A number shown just above the pill (unread messages); nothing when 0.
  final int badge;

  @override
  Widget build(BuildContext context) {
    final pill = GestureDetector(
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
    if (badge <= 0) return pill;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        pill,
        // Sits on the top edge of the pill, just above the label.
        Positioned(
          top: -8,
          right: 6,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.pink,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.bg1, width: 1.5),
              ),
              child: Text(
                badge > 9 ? '9+' : '$badge',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
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
