import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/datasources/local/prefs_source.dart';
import '../../../shared/animations/breathe_animation.dart';
import '../../../shared/widgets/pulse_rings.dart';
import '../../../shared/widgets/centered_scroll.dart';
import '../bloc/onboarding_bloc.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OnboardingBloc(prefsSource: GetIt.I<PrefsSource>()),
      child: BlocListener<OnboardingBloc, OnboardingState>(
        listener: (context, state) {
          if (state.done) context.go(RouteNames.login);
        },
        child: const _OnboardingBody(),
      ),
    );
  }
}

class _OnboardingBody extends StatefulWidget {
  const _OnboardingBody();
  @override
  State<_OnboardingBody> createState() => _OnboardingBodyState();
}

class _OnboardingBodyState extends State<_OnboardingBody> {
  final _pageCtrl = PageController();

  static const _slides = [
    _Slide('Feel close,\neven from far away.',
        'Usync creates a shared emotional space that keeps two hearts in sync across any distance.',
        _SlideVisual.connectedOrbs),
    _Slide('Share emotions\nin realtime.',
        'Send your mood, your heartbeat, and your presence — instantly and beautifully.',
        _SlideVisual.emotionWave),
    _Slide('Create moments\ntogether.',
        'Draw, doodle, and leave glowing traces on a shared canvas that only you two can see.',
        _SlideVisual.doodle),
    _Slide('Stay connected\neverywhere.',
        'Widgets, ambient presence, and gentle notifications keep your connection alive all day.',
        _SlideVisual.presence),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<OnboardingBloc>();
    return BlocBuilder<OnboardingBloc, OnboardingState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.bg1,
          body: Stack(
            children: [
              PageView.builder(
                controller: _pageCtrl,
                onPageChanged: (i) => bloc.add(PageChanged(i)),
                itemCount: _slides.length,
                itemBuilder: (_, i) => _SlideWidget(slide: _slides[i]),
              ),
              // Footer
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    left: 36, right: 36, bottom: 50 + MediaQuery.paddingOf(context).bottom,
                    top: 24,
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => bloc.add(OnboardingSkipped()),
                        child: const Text('Skip', style: TextStyle(color: AppColors.textDim, fontSize: 14)),
                      ),
                      const Spacer(),
                      // Dots
                      Row(
                        children: List.generate(4, (i) {
                          final active = i == state.currentPage;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 350),
                            margin: const EdgeInsets.symmetric(horizontal: 3.5),
                            width:  active ? 26 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: active ? AppColors.pink : AppColors.textDim,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: active
                                  ? [BoxShadow(color: AppColors.pink.withValues(alpha: 0.6), blurRadius: 10)]
                                  : null,
                            ),
                          );
                        }),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          if (state.isLastPage) {
                            bloc.add(OnboardingCompleted());
                          } else {
                            _pageCtrl.nextPage(
                              duration: const Duration(milliseconds: 550),
                              curve: const Cubic(0.4, 0, 0.2, 1),
                            );
                            bloc.add(PageAdvanced());
                          }
                        },
                        child: Container(
                          width: 62, height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                            ),
                            boxShadow: [
                              BoxShadow(color: AppColors.pink.withValues(alpha: 0.4), blurRadius: 25),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              state.isLastPage ? '✓' : '›',
                              style: const TextStyle(color: Colors.white, fontSize: 24),
                            ),
                          ),
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

class _Slide {
  const _Slide(this.headline, this.subtext, this.visual);
  final String      headline;
  final String      subtext;
  final _SlideVisual visual;
}

enum _SlideVisual { connectedOrbs, emotionWave, doodle, presence }

class _SlideWidget extends StatelessWidget {
  const _SlideWidget({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 6,
          child: _buildVisual(slide.visual),
        ),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            // Scrolls when a large font size makes the text taller than its space.
            child: CenteredScroll(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(slide.headline, textAlign: TextAlign.center, style: AppTextStyles.h1),
                const SizedBox(height: 14),
                Text(slide.subtext, textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
              ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildVisual(_SlideVisual v) {
    return switch (v) {
      _SlideVisual.connectedOrbs => const _ConnectedOrbsVisual(),
      _SlideVisual.emotionWave   => const _EmotionWaveVisual(),
      _SlideVisual.doodle        => const _DoodleVisual(),
      _SlideVisual.presence      => const _PresenceVisual(),
    };
  }
}

class _ConnectedOrbsVisual extends StatelessWidget {
  const _ConnectedOrbsVisual();
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 150, height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.pink.withValues(alpha: 0.5), AppColors.purple.withValues(alpha: 0.5)],
            ),
          ),
        ),
        Positioned(
          left: 60,
          child: BreatheAnimation(
            child: Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [AppColors.pinkLight, AppColors.pink],
                  center: Alignment(-0.3, -0.3),
                ),
                boxShadow: [BoxShadow(color: AppColors.pink.withValues(alpha: 0.5), blurRadius: 40)],
              ),
              child: const Center(child: Text('👤', style: TextStyle(fontSize: 36))),
            ),
          ),
        ),
        Positioned(
          right: 60,
          child: BreatheAnimation(
            delay: const Duration(milliseconds: 600),
            child: Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [AppColors.lavender, AppColors.purple],
                  center: Alignment(-0.3, -0.3),
                ),
                boxShadow: [BoxShadow(color: AppColors.purple.withValues(alpha: 0.5), blurRadius: 40)],
              ),
              child: const Center(child: Text('👤', style: TextStyle(fontSize: 36))),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmotionWaveVisual extends StatelessWidget {
  const _EmotionWaveVisual();
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        PulseRings(color: AppColors.pink, count: 3, size: 250, staggerMs: 800),
        BreatheAnimation(
          child: Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.pink.withValues(alpha: 0.2),
              border: Border.all(color: AppColors.pink.withValues(alpha: 0.3)),
            ),
            child: const Center(child: Text('💖', style: TextStyle(fontSize: 44))),
          ),
        ),
      ],
    );
  }
}

class _DoodleVisual extends StatelessWidget {
  const _DoodleVisual();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280, height: 200,
      child: CustomPaint(painter: _DoodlePainter()),
    );
  }
}

class _DoodlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3);

    paint.color = AppColors.pinkLight.withValues(alpha: 0.9);
    final path1 = Path()
      ..moveTo(30, 160)
      ..cubicTo(60, 100, 90, 80, 130, 110)
      ..cubicTo(160, 130, 180, 80, 220, 60)
      ..lineTo(270, 90);
    canvas.drawPath(path1, paint);

    paint.color = AppColors.lavender.withValues(alpha: 0.7);
    final path2 = Path()
      ..moveTo(20, 120)
      ..cubicTo(50, 140, 80, 90, 110, 70)
      ..cubicTo(140, 50, 160, 90, 190, 110)
      ..lineTo(260, 110);
    canvas.drawPath(path2, paint);

    canvas.drawCircle(const Offset(130, 110), 6,
        Paint()..color = AppColors.pinkLight.withValues(alpha: 0.8)..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4));
    canvas.drawCircle(const Offset(220, 60), 5,
        Paint()..color = AppColors.lavender.withValues(alpha: 0.7)..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3));
  }

  @override
  bool shouldRepaint(_) => false;
}

class _PresenceVisual extends StatefulWidget {
  const _PresenceVisual();
  @override
  State<_PresenceVisual> createState() => _PresenceVisualState();
}

class _PresenceVisualState extends State<_PresenceVisual> with TickerProviderStateMixin {
  final List<AnimationController> _arcs = [];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 3; i++) {
      final c = AnimationController(vsync: this, duration: const Duration(seconds: 20));
      _arcs.add(c);
      c.repeat(reverse: i == 1);
    }
  }

  @override
  void dispose() {
    for (final c in _arcs) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = [AppColors.pink, AppColors.purple, AppColors.cyan];
    return SizedBox(
      width: 300, height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(3, (i) {
            final size = 160.0 + i * 60;
            return AnimatedBuilder(
              animation: _arcs[i],
              builder: (_, __) => Transform.rotate(
                angle: _arcs[i].value * 3.14159 * 2 * (i == 1 ? -1 : 1),
                child: Container(
                  width: size, height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08), style: BorderStyle.solid),
                  ),
                ),
              ),
            );
          }),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              return BreatheAnimation(
                delay: Duration(milliseconds: i * 300),
                child: Container(
                  width: 16, height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: dots[i],
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: dots[i].withValues(alpha: 0.6), blurRadius: 20)],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
