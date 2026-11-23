import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/services/pen_sound.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_snack_bar.dart';
import '../../../../core/utils/haptic_util.dart';
import '../../../../domain/games/pen_fight.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/pen_fight_bloc.dart';

class PenFightScreen extends StatelessWidget {
  const PenFightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    return BlocProvider(
      create: (_) => GetIt.I<PenFightBloc>()
        ..add(PenFightOpened(coupleId: user?.coupleId ?? '', userId: user?.id ?? '')),
      child: BlocListener<PenFightBloc, PenFightState>(
        listenWhen: (_, b) => b.error != null,
        listener: (context, state) =>
            ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: Text(state.error!))),
        child: _Body(userId: user?.id ?? ''),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.userId});
  final String userId;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> with SingleTickerProviderStateMixin {
  final _sound = PenSound();
  late final Ticker _ticker;
  /// The level offered on the start screen (what the next game will use).
  PenDifficulty _level = PenDifficulty.normal;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    final bloc = context.read<PenFightBloc>();
    // Drives the simulation: the bloc turns the elapsed time into fixed steps.
    _ticker = createTicker((elapsed) {
      final delta = elapsed - _last;
      _last = elapsed;
      if (bloc.state.moving) bloc.add(PenTicked(delta));
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<PenFightBloc, PenFightState>(
          listenWhen: (a, b) => b.world.bumps > a.world.bumps,
          listener: (_, __) {
            HapticUtil.medium();
            _sound.play();
          },
        ),
        BlocListener<PenFightBloc, PenFightState>(
          listenWhen: (a, b) => !a.roundOver && b.roundOver,
          listener: (_, __) => HapticUtil.heavy(),
        ),
      ],
      child: Scaffold(
        backgroundColor: AppColors.bg1,
        body: SafeArea(
          child: BlocBuilder<PenFightBloc, PenFightState>(
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
                        Expanded(child: Text('Pen fight', style: AppTextStyles.h2.copyWith(fontSize: 22))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: state.loading
                          ? const Center(child: LoadingDots())
                          : active
                              ? _Match(state: state, userId: widget.userId)
                              : Center(
                                  child: _Idle(
                                    finished: state.session != null,
                                    level: _level,
                                    onLevel: (d) => setState(() => _level = d),
                                  ),
                                ),
                    ),
                  ),
                  if (!state.loading)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: !active
                            ? GlowButton(
                                label: state.session == null ? 'Start a game' : 'Play again',
                                isLoading: state.busy,
                                onTap: () => context.read<PenFightBloc>().add(PenFightStarted(_level)),
                              )
                            : Column(
                                children: [
                                  if (state.roundOver)
                                    GlowButton(
                                      label: 'Next round',
                                      onTap: () => context.read<PenFightBloc>().add(PenNextRound()),
                                    ),
                                  TextButton(
                                    onPressed: () => context.read<PenFightBloc>().add(PenFightEnded()),
                                    child: const Text('End game', style: TextStyle(color: AppColors.textMuted)),
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
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.finished, required this.level, required this.onLevel});
  final bool finished;
  final PenDifficulty level;
  final ValueChanged<PenDifficulty> onLevel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🖊️', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(finished ? 'Game over' : 'Flick your pen', style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'Take turns flicking your pen across the desk. Knock your partner\'s pen off the edge to win the round. '
              'Rounds go on until one of you ends the game. Both of you need to open the game.',
              style: AppTextStyles.bodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              children: [
                for (final d in PenDifficulty.values)
                  ChoiceChip(
                    label: Text(d.label),
                    selected: d == level,
                    onSelected: (_) => onLevel(d),
                    selectedColor: AppColors.pink.withValues(alpha: 0.35),
                    backgroundColor: AppColors.glass,
                    labelStyle: const TextStyle(color: AppColors.textPrimary),
                    side: const BorderSide(color: AppColors.glassBorder),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(level.description, style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
          ],
        ),
      );
}

class _Match extends StatefulWidget {
  const _Match({required this.state, required this.userId});
  final PenFightState state;
  final String userId;

  @override
  State<_Match> createState() => _MatchState();
}

class _MatchState extends State<_Match> {
  /// Where the finger is while aiming, in desk units; null when not aiming.
  Offset? _aim;

  /// Margin around the desk (px), so a pen that falls off stays visible.
  static const _margin = 28.0;
  static const _maxPull = 0.35;

  String _status(PenFightState s) {
    final name = s.players.partnerName;
    if (!s.partnerHere) return 'Waiting for $name to open the game…';
    switch (s.roundOutcome) {
      case PenOutcome.ownWon:   return 'You knocked it off! 🎯';
      case PenOutcome.otherWon: return 'Your pen fell! 😅';
      case PenOutcome.draw:     return 'Both pens fell!';
      case PenOutcome.none:     break;
    }
    if (s.moving) return '…';
    return s.turnUserId == widget.userId ? 'Your turn: pull back your pen and let go' : '$name is aiming…';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final myTurn = s.turnUserId == widget.userId && s.partnerHere && !s.moving && !s.roundOver;
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Score(label: 'You', value: s.myScore, color: AppColors.pink),
            const SizedBox(width: 24),
            Text('Round ${s.round} · ${s.difficulty.label}', style: AppTextStyles.bodyMuted),
            const SizedBox(width: 24),
            _Score(label: s.players.partnerName, value: s.partnerScore, color: AppColors.cyan),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(_status(s), style: AppTextStyles.h3.copyWith(fontSize: 16), textAlign: TextAlign.center),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            // Largest desk (1 : 1.4) that fits, centred.
            final scale = min((box.maxWidth - 2 * _margin) / PenFight.deskWidth,
                (box.maxHeight - 2 * _margin) / PenFight.deskHeight);
            final w = scale * PenFight.deskWidth + 2 * _margin;
            final h = scale * PenFight.deskHeight + 2 * _margin;
            Offset toDesk(Offset p) => Offset((p.dx - _margin) / scale, (p.dy - _margin) / scale);
            return Center(
              child: SizedBox(
                width: w,
                height: h,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    if (!myTurn) return;
                    final p = toDesk(d.localPosition);
                    final pen = s.world.own;
                    // Grab the pen: a generous area around it.
                    if ((p - Offset(pen.x, pen.y)).distance <= PenFight.penRadius * 2.5) setState(() => _aim = p);
                  },
                  onPanUpdate: (d) {
                    if (_aim != null) setState(() => _aim = toDesk(d.localPosition));
                  },
                  onPanEnd: (_) => _release(context),
                  onPanCancel: () => setState(() => _aim = null),
                  child: CustomPaint(
                    painter: _PenFightPainter(
                      world: s.world,
                      scale: scale,
                      margin: _margin,
                      aim: _aim,
                      maxPull: _maxPull,
                      glow: myTurn,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  void _release(BuildContext context) {
    final aim = _aim;
    setState(() => _aim = null);
    if (aim == null) return;
    final pen = widget.state.world.own;
    // Slingshot: the pen goes the opposite way to the pull.
    final dx = pen.x - aim.dx, dy = pen.y - aim.dy;
    final power = min(sqrt(dx * dx + dy * dy) / _maxPull, 1.0);
    if (power < 0.1) return;
    context.read<PenFightBloc>().add(PenFlicked(dx, dy, power));
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
          Text('$value', style: AppTextStyles.h2.copyWith(color: color, fontSize: 26)),
          Text(label, style: AppTextStyles.bodyMuted.copyWith(fontSize: 11)),
        ],
      );
}

class _PenFightPainter extends CustomPainter {
  _PenFightPainter({
    required this.world,
    required this.scale,
    required this.margin,
    required this.aim,
    required this.maxPull,
    required this.glow,
  });

  final PenWorld world;
  final double scale, margin, maxPull;
  final Offset? aim;
  final bool glow;

  Offset _px(double x, double y) => Offset(margin + x * scale, margin + y * scale);

  @override
  void paint(Canvas canvas, Size size) {
    // The desk.
    final desk = RRect.fromRectAndRadius(
      Rect.fromLTWH(margin, margin, PenFight.deskWidth * scale, PenFight.deskHeight * scale),
      const Radius.circular(18),
    );
    canvas.drawRRect(desk, Paint()..color = AppColors.glass);
    canvas.drawRRect(
      desk,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = glow ? AppColors.pink.withValues(alpha: 0.7) : AppColors.glassBorder,
    );
    // Centre line.
    canvas.drawLine(
      _px(0.04, PenFight.deskHeight / 2),
      _px(PenFight.deskWidth - 0.04, PenFight.deskHeight / 2),
      Paint()
        ..color = AppColors.glassMid
        ..strokeWidth = 1,
    );

    // Aim: a line back to the finger and a dotted path showing where the flick goes.
    final a = aim;
    if (a != null) {
      final pen = world.own;
      final pull = Offset(pen.x - a.dx, pen.y - a.dy);
      final power = min(pull.distance / maxPull, 1.0);
      if (pull.distance > 0) {
        final dir = pull / pull.distance;
        canvas.drawLine(_px(pen.x, pen.y), _px(a.dx, a.dy), Paint()
          ..color = AppColors.textMuted
          ..strokeWidth = 2);
        final dot = Paint()..color = Color.lerp(AppColors.cyan, AppColors.pink, power)!.withValues(alpha: 0.8);
        for (var i = 1; i <= 7; i++) {
          final d = i * 0.07 * (0.4 + power);
          canvas.drawCircle(_px(pen.x + dir.dx * d, pen.y + dir.dy * d), 3.5, dot);
        }
      }
    }

    // The rubbers.
    for (final o in world.difficulty.obstacles) {
      final c = _px(o.x, o.y), r = o.radius * scale;
      canvas.drawCircle(c + const Offset(2, 3), r, Paint()..color = Colors.black.withValues(alpha: 0.35));
      canvas.drawCircle(c, r, Paint()..color = AppColors.lavender.withValues(alpha: 0.55));
      canvas.drawCircle(c, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.lavender);
    }

    _drawPen(canvas, world.other, AppColors.cyan);
    _drawPen(canvas, world.own, AppColors.pink);
  }

  void _drawPen(Canvas canvas, PenBody pen, Color color) {
    final c = _px(pen.x, pen.y);
    final len = 0.24 * scale, thick = 0.05 * scale;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(pen.angle);
    if (pen.fell) canvas.scale(0.8);
    final alpha = pen.fell ? 0.45 : 1.0;
    // Shadow, body, tip and cap.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(2, 3), width: len, height: thick), Radius.circular(thick / 2)),
      Paint()..color = Colors.black.withValues(alpha: 0.35 * alpha),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: len, height: thick), Radius.circular(thick / 2)),
      Paint()..color = color.withValues(alpha: alpha),
    );
    final tip = Path()
      ..moveTo(len / 2, -thick / 2)
      ..lineTo(len / 2 + thick * 0.9, 0)
      ..lineTo(len / 2, thick / 2)
      ..close();
    canvas.drawPath(tip, Paint()..color = Colors.white.withValues(alpha: 0.85 * alpha));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-len / 2, -thick / 2, thick * 1.1, thick), Radius.circular(thick / 3)),
      Paint()..color = Colors.white.withValues(alpha: 0.7 * alpha),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PenFightPainter old) =>
      old.world != world || old.aim != aim || old.glow != glow || old.scale != scale;
}
