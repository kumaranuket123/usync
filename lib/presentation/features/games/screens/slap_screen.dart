import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/services/slap_sound.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_snack_bar.dart';
import '../../../../core/utils/haptic_util.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/slap_bloc.dart';

class SlapScreen extends StatelessWidget {
  const SlapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    return BlocProvider(
      create: (_) => GetIt.I<SlapBloc>()
        ..add(
            SlapOpened(coupleId: user?.coupleId ?? '', userId: user?.id ?? '')),
      child: BlocListener<SlapBloc, SlapState>(
        listenWhen: (_, b) => b.error != null,
        listener: (context, state) => ScaffoldMessenger.of(context)
            .showSnackBar(appSnackBar(content: Text(state.error!))),
        child: const _Body(),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> with TickerProviderStateMixin {
  /// 0 -> 1 each time a slap lands on this user: shakes the screen and flashes it red.
  late final AnimationController _hit = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));

  /// 0 -> 1 each time this user slaps: the hand swings.
  late final AnimationController _swing = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220));

  final _sound = SlapSound();

  @override
  void dispose() {
    _sound.dispose();
    _hit.dispose();
    _swing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<SlapBloc, SlapState>(
          listenWhen: (a, b) => b.received > a.received,
          listener: (_, __) {
            HapticUtil.heavy();
            _sound.play();
            _hit.forward(from: 0);
          },
        ),
        // Only a slap the bloc counted (not one dropped by its rate limit) swings the hand.
        BlocListener<SlapBloc, SlapState>(
          listenWhen: (a, b) => b.given > a.given,
          listener: (_, __) {
            HapticUtil.medium();
            _sound.play();
            _swing.forward(from: 0);
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: AppColors.bg1,
        body: AnimatedBuilder(
          animation: _hit,
          builder: (context, child) {
            final t = _hit.value;
            final shake = sin(t * pi * 8) * (1 - t) * 14;
            return Stack(
              children: [
                Transform.translate(offset: Offset(shake, 0), child: child),
                // Red flash that fades out.
                if (_hit.isAnimating)
                  Positioned.fill(
                    child: IgnorePointer(
                        child: ColoredBox(
                            color: AppColors.pink
                                .withValues(alpha: 0.35 * (1 - t)))),
                  ),
              ],
            );
          },
          child: SafeArea(
            child: BlocBuilder<SlapBloc, SlapState>(
              builder: (context, state) {
                final active = state.session?.isActive ?? false;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                      child: Row(
                        children: [
                          const NeonBackButton(),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Text('Slap fight',
                                  style:
                                      AppTextStyles.h2.copyWith(fontSize: 22))),
                        ],
                      ),
                    ),
                    // Full width: in a start-aligned column the content would shrink to its own
                    // width and sit at the left.
                    Expanded(
                      child: SizedBox(
                        width: double.infinity,
                        child: state.loading
                            ? const Center(child: LoadingDots())
                            : Center(
                                child: active
                                    ? _Arena(
                                        state: state,
                                        swing: _swing,
                                        onSlap: () => context
                                            .read<SlapBloc>()
                                            .add(SlapSent()))
                                    : _Idle(
                                        finished: state.session != null,
                                        state: state),
                              ),
                      ),
                    ),
                    if (!state.loading)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                        child: SizedBox(
                          width: double.infinity,
                          child: Column(
                            children: [
                              if (!active)
                                GlowButton(
                                  label: state.session == null
                                      ? 'Start a game'
                                      : 'Play again',
                                  isLoading: state.busy,
                                  onTap: () => context
                                      .read<SlapBloc>()
                                      .add(SlapStarted()),
                                )
                              else
                                TextButton(
                                  onPressed: () =>
                                      context.read<SlapBloc>().add(SlapEnded()),
                                  child: const Text('End game',
                                      style: TextStyle(
                                          color: AppColors.textMuted)),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.finished, required this.state});
  final bool finished;
  final SlapState state;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🖐️', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(finished ? 'Fight over' : 'Slap each other',
                style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              finished
                  ? 'You gave ${state.given}, you took ${state.received}.'
                  : 'Both open the game and tap away. Every slap lands on your partner\'s phone at once, with a shake. All in good fun!',
              style: AppTextStyles.bodyMuted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

class _Arena extends StatelessWidget {
  const _Arena(
      {required this.state, required this.swing, required this.onSlap});
  final SlapState state;
  final Animation<double> swing;
  final VoidCallback onSlap;

  @override
  Widget build(BuildContext context) {
    final players = state.players;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Your partner: takes the hit when you slap.
        _Avatar(
          emoji: players.partnerEmoji,
          name: players.partnerName,
          hits: state.given,
          hurtEmoji: '😵',
          bubble: 'Ouch!',
          color: AppColors.cyan,
          direction: 1,
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Score(label: 'Given', value: state.given, color: AppColors.cyan),
            const SizedBox(width: 40),
            _Score(
                label: 'Taken', value: state.received, color: AppColors.pink),
          ],
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTapDown: (_) => onSlap(),
          child: AnimatedBuilder(
            animation: swing,
            builder: (_, child) => Transform.rotate(
              angle: -sin(swing.value * pi) * 0.7,
              child: Transform.scale(
                  scale: 1 + sin(swing.value * pi) * 0.25, child: child),
            ),
            child: Container(
              width: 150,
              height: 150,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.glass,
                border: Border.all(color: AppColors.pink, width: 2),
              ),
              child: const Text('🖐️', style: TextStyle(fontSize: 72)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Tap to slap ${players.partnerName}',
            style: AppTextStyles.bodyMuted),
        const SizedBox(height: 20),
        // You: take the hit when your partner slaps.
        _Avatar(
          emoji: players.ownEmoji,
          name: 'You',
          hits: state.received,
          hurtEmoji: '😖',
          bubble: 'Ow!',
          color: AppColors.pink,
          direction: -1,
          size: 64,
        ),
      ],
    );
  }
}

/// A player's avatar. Each time [hits] goes up it is knocked sideways, its face turns to
/// [hurtEmoji], a "💥" pops and a [bubble] shows, so you can see that the slap landed.
class _Avatar extends StatefulWidget {
  const _Avatar({
    required this.emoji,
    required this.name,
    required this.hits,
    required this.hurtEmoji,
    required this.bubble,
    required this.color,
    required this.direction,
    this.size = 84,
  });

  final String emoji, name, hurtEmoji, bubble;
  final int hits;
  final Color color;

  /// Which way the slap knocks the avatar (1 right, -1 left).
  final double direction;
  final double size;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void didUpdateWidget(_Avatar old) {
    super.didUpdateWidget(old);
    if (widget.hits > old.hits) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final hurt = _c.isAnimating && t < 0.85;
        // A quick knock to the side that wobbles back.
        final knock = sin(t * pi * 5) * (1 - t) * 26 * widget.direction;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: size + 34,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Transform.translate(
                    offset: Offset(knock, 18),
                    child: Transform.rotate(
                      angle: knock / 120,
                      child: Container(
                        width: size,
                        height: size,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.lerp(
                              AppColors.glass,
                              AppColors.pink.withValues(alpha: 0.45),
                              hurt ? 1 - t : 0),
                          border: Border.all(color: widget.color, width: 2),
                        ),
                        child: Text(hurt ? widget.hurtEmoji : widget.emoji,
                            style: TextStyle(fontSize: size * 0.5)),
                      ),
                    ),
                  ),
                  if (hurt) ...[
                    Positioned(
                      right: -4 + 10 * (1 - widget.direction) / 2,
                      top: 18,
                      child: Opacity(
                        opacity: 1 - t,
                        child: Transform.scale(
                            scale: 0.6 + t * 1.2,
                            child: const Text('💥',
                                style: TextStyle(fontSize: 30))),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      child: Opacity(
                        opacity: (1 - t).clamp(0, 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                              color: widget.color,
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(widget.bubble,
                              style: AppTextStyles.label.copyWith(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(widget.name, style: AppTextStyles.label),
          ],
        );
      },
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('$value', style: AppTextStyles.h1.copyWith(color: color)),
          Text(label, style: AppTextStyles.label),
        ],
      );
}
