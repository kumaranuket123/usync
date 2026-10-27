import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/animations/breathe_animation.dart';
import '../../../shared/widgets/gradient_text.dart';
import '../../../shared/widgets/particle_field.dart';
import '../../../shared/widgets/pulse_rings.dart';
import '../bloc/auth_bloc.dart';
import '../../../../core/utils/app_snack_bar.dart';
import '../../../../core/utils/privacy_policy.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          final route = state.user.coupleId != null ? RouteNames.home : RouteNames.pairInvite;
          context.go(route);
        } else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: Text(state.message)));
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg1,
        body: Stack(
          children: [
            Container(decoration: const BoxDecoration(gradient: AppGradients.background)),
            const ParticleField(count: 25),
            SafeArea(
              // Fills the screen, but scrolls instead of overflowing on a small phone or large font.
              child: CustomScrollView(slivers: [SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    const _Hero(),
                    const SizedBox(height: 36),
                    GradientText('USYNC', gradient: AppGradients.gradientText2, style: AppTextStyles.logoLarge.copyWith(fontSize: 38, letterSpacing: 8)),
                    const SizedBox(height: 16),
                    Text(
                      'Feel close, even from far away.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textPrimary.withValues(alpha: 0.8)),
                    ),
                    const Spacer(flex: 4),
                    const _GoogleButton(),
                    const SizedBox(height: 18),
                    Text(
                      'Your account is only used to sign you in\nand to connect you with your partner.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelSmall.copyWith(height: 1.5),
                    ),
                    TextButton(
                      onPressed: () => openPrivacyPolicy(context),
                      child: Text('Privacy Policy', style: AppTextStyles.labelSmall.copyWith(decoration: TextDecoration.underline)),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ))]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two glowing hearts inside slow pulse rings.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240, height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const PulseRings(size: 220),
          Positioned(left: 40, child: _Orb('💖', const [AppColors.pinkLight, AppColors.pink], AppColors.pink, Duration.zero)),
          Positioned(right: 40, child: _Orb('💜', const [AppColors.lavender, AppColors.purple], AppColors.purple, const Duration(milliseconds: 500))),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb(this.emoji, this.colors, this.glow, this.delay);
  final String emoji;
  final List<Color> colors;
  final Color glow;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return BreatheAnimation(
      delay: delay,
      child: Container(
        width: 84, height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors, center: const Alignment(-0.3, -0.3)),
          boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.55), blurRadius: 32)],
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 36))),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final loading = state is AuthLoading;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          elevation: 6,
          shadowColor: AppColors.purple.withValues(alpha: 0.5),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: loading ? null : () => context.read<AuthBloc>().add(const GoogleSignInRequested()),
            child: SizedBox(
              height: 58,
              width: double.infinity,
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.purple),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 22, height: 22, child: CustomPaint(painter: _GoogleGPainter())),
                          const SizedBox(width: 12),
                          // Shrinks instead of overflowing on a narrow phone or a large font.
                          const Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Continue with Google',
                                style: TextStyle(
                                  color: Color(0xFF1F1F1F), fontSize: 16, fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The multicolour Google "G".
class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final stroke = size.width * 0.22;
    final rect = Rect.fromCircle(center: c, radius: r - stroke / 2);
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Angles run clockwise from 3 o'clock; the gap on the right is the G's opening.
    canvas.drawArc(rect, _rad(-45), _rad(-90), false, arc(const Color(0xFFEA4335)));  // top, red
    canvas.drawArc(rect, _rad(-135), _rad(-90), false, arc(const Color(0xFFFBBC05))); // left, yellow
    canvas.drawArc(rect, _rad(135), _rad(-90), false, arc(const Color(0xFF34A853)));  // bottom, green
    canvas.drawArc(rect, _rad(45), _rad(-45), false, arc(const Color(0xFF4285F4)));   // lower right, blue
    // The bar of the G.
    canvas.drawRect(
      Rect.fromLTRB(c.dx, c.dy - stroke / 2, c.dx + r, c.dy + stroke / 2),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
