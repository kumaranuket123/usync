import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../shared/animations/breathe_animation.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_text.dart';
import '../../../shared/widgets/heartbeat_visualizer.dart';
import '../../../shared/widgets/live_indicator.dart';
import '../bloc/widgets_bloc.dart';

class WidgetsScreen extends StatelessWidget {
  const WidgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth     = context.read<AuthBloc>().state;
    final coupleId = auth is Authenticated ? (auth.user.coupleId ?? '') : '';
    return BlocProvider(
      create: (_) => GetIt.I<WidgetsBloc>()..add(WidgetsLoaded(coupleId)),
      child: const _WidgetsBody(),
    );
  }
}

class _WidgetsBody extends StatelessWidget {
  const _WidgetsBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Widgets', style: AppTextStyles.h2),
                  Text('Add to your home screen', style: AppTextStyles.label),
                ],
              ),
            ),
            Expanded(
              child: GridView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:  2,
                  mainAxisSpacing: 13,
                  crossAxisSpacing:13,
                  childAspectRatio: 0.70,
                ),
                children: [
                  // Heartbeat
                  _WidgetCard(
                    icon: '💓', name: 'Heartbeat', desc: 'Live pulse from your partner',
                    glowColor: AppColors.pink,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: HeartbeatVisualizer(width: 120, height: 30),
                    ),
                  ),

                  // Mood
                  _WidgetCard(
                    icon: '💭', name: 'Mood', desc: "Partner's current vibe",
                    glowColor: AppColors.purple,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: GlassCard(
                        borderRadius: 12,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Column(
                          children: [
                            const Text('😊', style: TextStyle(fontSize: 22)),
                            Text('Happy', style: AppTextStyles.labelSmall),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Doodle
                  _WidgetCard(
                    icon: '✏️', name: 'Live Doodle', desc: 'See sketches in real time',
                    glowColor: AppColors.cyan,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: CustomPaint(
                        size: const Size(120, 40),
                        painter: _DoodlePreviewPainter(),
                      ),
                    ),
                  ),

                  // Presence
                  _WidgetCard(
                    icon: '🌐', name: 'Presence', desc: 'Is your partner nearby?',
                    glowColor: AppColors.pinkLight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: LiveIndicator(label: 'Active 2m ago', color: AppColors.cyan),
                    ),
                  ),

                  // Streak (full width)
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.glass,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('🔥', style: TextStyle(fontSize: 32)),
                              const SizedBox(height: 6),
                              Text('Connection Streak', style: AppTextStyles.label.copyWith(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                              Text("You've been in sync every day", style: AppTextStyles.labelSmall),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            BlocBuilder<WidgetsBloc, WidgetsBlocState>(
                              builder: (context, state) {
                                final streak = state is WidgetsReady
                                    ? state.couple.streakDays.toString()
                                    : '—';
                                return GradientText(streak, gradient: AppGradients.gradientText2,
                                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800));
                              },
                            ),
                            Text('days', style: AppTextStyles.label),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WidgetCard extends StatelessWidget {
  const _WidgetCard({required this.icon, required this.name, required this.desc, required this.glowColor, this.child});
  final String icon;
  final String name, desc;
  final Color  glowColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return BreatheAnimation(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Glow blob — positioned relative to the card, clipped by Stack
          Positioned(
            top: -20, right: -20,
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [glowColor.withOpacity(0.4), Colors.transparent],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.glassBorder),
            ),
            padding: const EdgeInsets.all(14),
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(icon, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 6),
                  Text(name,
                      style: AppTextStyles.label.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(desc, style: AppTextStyles.labelSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (child != null) child!,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoodlePreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF6EC7).withOpacity(0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.5);

    final path = Path()
      ..moveTo(5, 20)
      ..cubicTo(20, 10, 35, 30, 50, 18)
      ..cubicTo(65, 6, 80, 28, 95, 16)
      ..lineTo(115, 20);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
