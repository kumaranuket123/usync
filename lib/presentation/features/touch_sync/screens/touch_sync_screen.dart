import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../shared/animations/breathe_animation.dart';
import '../../../shared/widgets/live_indicator.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/centered_scroll.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../../shared/widgets/pulse_rings.dart';
import '../bloc/touch_sync_bloc.dart';

class TouchSyncScreen extends StatelessWidget {
  const TouchSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.I<TouchSyncBloc>(),
      child: const _TouchSyncBody(),
    );
  }
}

class _TouchSyncBody extends StatefulWidget {
  const _TouchSyncBody();
  @override
  State<_TouchSyncBody> createState() => _TouchSyncBodyState();
}

class _TouchSyncBodyState extends State<_TouchSyncBody> {
  @override
  void initState() {
    super.initState();
    _mount();
  }

  Future<void> _mount() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final user = await GetIt.I<IAuthRepository>().getCurrentUser();
    if (user?.coupleId == null) return;

    final couple = await GetIt.I<ICoupleRepository>().getCouple(user!.coupleId!);
    final partnerId = couple.partnerIdFor(uid);

    if (!mounted) return;
    context.read<TouchSyncBloc>().add(TouchScreenMounted(
      coupleId:      couple.id,
      userId:        uid,
      partnerUserId: partnerId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: BlocBuilder<TouchSyncBloc, TouchSyncState>(
        builder: (context, state) {
          if (state is TouchSyncConnecting) {
            return const Center(child: LoadingDots());
          }

          final ready     = state as TouchSyncReady;
          final isOwner   = ready.isOwnerTouching;
          final isPartner = ready.isPartnerTouching;

          return Stack(
            children: [
              // Ambient cyan glow
              Center(
                child: Container(
                  width: 700, height: 700,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [AppColors.cyan.withValues(alpha: 0.04), Colors.transparent],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Row(
                        children: [
                          const NeonBackButton(),
                          const SizedBox(width: 14),
                          Text('Touch Sync', style: AppTextStyles.h4),
                        ],
                      ),
                    ),

                    // Scrolls when a large font or display size makes the content taller than the space.
                    Expanded(
                      child: CenteredScroll(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                    // Touch area
                    SizedBox(
                      width: 300, height: 300,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PulseRings(
                            color:     AppColors.cyan,
                            count:     3,
                            size:      280,
                            staggerMs: 800,
                            cycleDuration: isOwner
                                ? const Duration(milliseconds: 1200)
                                : const Duration(milliseconds: 3000),
                          ),
                          if (isPartner)
                            PulseRings(color: AppColors.pinkLight, count: 2, size: 220, staggerMs: 600),
                          GestureDetector(
                            onTapDown:   (_) => context.read<TouchSyncBloc>().add(TouchPressed()),
                            onTapUp:     (_) => context.read<TouchSyncBloc>().add(TouchReleased()),
                            onTapCancel: ()  => context.read<TouchSyncBloc>().add(TouchReleased()),
                            onLongPressStart: (_) => context.read<TouchSyncBloc>().add(TouchPressed()),
                            onLongPressEnd:   (_) => context.read<TouchSyncBloc>().add(TouchReleased()),
                            child: BreatheAnimation(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                child: Text(
                                  '🫰',
                                  style: TextStyle(
                                    fontSize: 90,
                                    shadows: [
                                      Shadow(
                                        color:      isOwner ? AppColors.cyan : AppColors.cyan.withValues(alpha: 0.65),
                                        blurRadius: isOwner ? 60 : 25,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Column(
                        children: [
                          Text(
                            isOwner   ? 'Sending…'          :
                            isPartner ? 'Partner is here!'  : 'Hold to sync',
                            style: AppTextStyles.h2.copyWith(fontSize: 26),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Press and hold the icon.\nYour partner will feel your touch.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMuted,
                          ),
                          const SizedBox(height: 28),
                          LiveIndicator(
                            label:    isPartner ? 'Partner is touching…' : 'Connected · Ready',
                            color:    AppColors.cyan,
                            isActive: ready.isConnected,
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
              ),
            ],
          );
        },
      ),
    );
  }
}
