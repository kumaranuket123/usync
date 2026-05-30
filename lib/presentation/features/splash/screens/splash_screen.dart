import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/datasources/local/prefs_source.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../shared/painters/conic_orb_painter.dart';
import '../../../shared/widgets/gradient_text.dart';
import '../../../shared/widgets/particle_field.dart';
import '../../../shared/widgets/pulse_rings.dart';
import '../bloc/splash_bloc.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SplashBloc(
        authRepository: GetIt.I<IAuthRepository>(),
        prefsSource:    GetIt.I<PrefsSource>(),
      )..add(SplashStarted()),
      child: BlocListener<SplashBloc, SplashState>(
        listener: (context, state) {
          if (state is SplashNavigating) {
            final route = switch (state.destination) {
              SplashDestination.onboarding => RouteNames.onboarding,
              SplashDestination.login      => RouteNames.login,
              SplashDestination.pairInvite => RouteNames.pairInvite,
              SplashDestination.home       => RouteNames.home,
            };
            context.go(route);
          }
        },
        child: const _SplashBody(),
      ),
    );
  }
}

class _SplashBody extends StatefulWidget {
  const _SplashBody();
  @override
  State<_SplashBody> createState() => _SplashBodyState();
}

class _SplashBodyState extends State<_SplashBody> with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _logoIn;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _logoIn = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
      ..forward();
  }

  @override
  void dispose() {
    _spin.dispose();
    _logoIn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Ambient purple glow
          Center(
            child: Container(
              width: 500, height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.purple.toRadialGlow(opacity: 0.25),
              ),
            ),
          ),

          const ParticleField(count: 40),

          // Logo
          Center(
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: _logoIn,
                curve: const Cubic(0.34, 1.56, 0.64, 1),
              ),
              child: FadeTransition(
                opacity: _logoIn,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 130, height: 130,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PulseRings(color: AppColors.pink, count: 3, size: 130),
                          AnimatedBuilder(
                            animation: _spin,
                            builder: (_, __) => CustomPaint(
                              size: const Size(130, 130),
                              painter: ConicOrbPainter(
                                angle: _spin.value * 2 * pi,
                                colors: const [
                                  AppColors.pink, AppColors.purple,
                                  AppColors.cyan, AppColors.purple, AppColors.pink,
                                ],
                              ),
                            ),
                          ),
                          Container(
                            width: 100, height: 100,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [AppColors.bg2, AppColors.bg1]),
                            ),
                            child: const Center(
                              child: Text('💫', style: TextStyle(fontSize: 40)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    GradientText(
                      'USYNC',
                      gradient: AppGradients.gradientText,
                      style: AppTextStyles.logoLarge,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'feel together',
                      style: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 13,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
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

extension _ColorExt on Color {
  RadialGradient toRadialGlow({double opacity = 0.25}) =>
      RadialGradient(colors: [withOpacity(opacity), withOpacity(0)]);
}
