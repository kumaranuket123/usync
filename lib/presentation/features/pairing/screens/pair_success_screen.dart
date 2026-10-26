import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/particle_field.dart';

class PairSuccessScreen extends StatefulWidget {
  const PairSuccessScreen({super.key});
  @override
  State<PairSuccessScreen> createState() => _PairSuccessScreenState();
}

class _PairSuccessScreenState extends State<PairSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    // The signed-in user now has a couple; screens read it from the app-wide AuthBloc.
    context.read<AuthBloc>().add(const AuthStateChecked());
    _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: Stack(
        children: [
          const ParticleField(count: 50),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _pop,
                      curve: const Cubic(0.34, 1.56, 0.64, 1),
                    ),
                    child: Container(
                      width: 130, height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [Color(0xCCFF6EC7), Color(0xCC9D4EDD)],
                          center: Alignment(-0.3, -0.3),
                        ),
                        boxShadow: [
                          BoxShadow(color: AppColors.pink.withValues(alpha: 0.5), blurRadius: 50),
                          BoxShadow(color: AppColors.purple.withValues(alpha: 0.3), blurRadius: 100),
                        ],
                      ),
                      child: const Center(child: Text('💞', style: TextStyle(fontSize: 54))),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text("You're connected!", style: AppTextStyles.h1.copyWith(fontSize: 30)),
                  const SizedBox(height: 12),
                  Text(
                    'Your emotional space is now live.\nYou and your partner are in sync.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMuted,
                  ),
                  const SizedBox(height: 40),
                  GlowButton(
                    label: 'Enter your space →',
                    onTap: () => context.go(RouteNames.home),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
