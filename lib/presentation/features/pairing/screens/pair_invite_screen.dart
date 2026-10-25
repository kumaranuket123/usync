import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/animations/breathe_animation.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/outline_button.dart';
import '../../../shared/widgets/particle_field.dart';
import '../../../../core/di/injection.dart';
import '../bloc/pairing_bloc.dart';

class PairInviteScreen extends StatelessWidget {
  const PairInviteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<PairingBloc>(),
      child: const _PairInviteBody(),
    );
  }
}

class _PairInviteBody extends StatefulWidget {
  const _PairInviteBody();
  @override
  State<_PairInviteBody> createState() => _PairInviteBodyState();
}

class _PairInviteBodyState extends State<_PairInviteBody> {
  @override
  void initState() {
    super.initState();
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) {
      context.read<PairingBloc>().add(GenerateCodeRequested(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PairingBloc, PairingState>(
      listener: (context, state) {
        if (state is PairingError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg1,
        body: Stack(
          children: [
            const ParticleField(count: 25),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Merging hearts visual
                      SizedBox(
                        width: 200, height: 120,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned(
                              left: 10,
                              child: BreatheAnimation(
                                child: Container(
                                  width: 80, height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const RadialGradient(colors: [AppColors.pinkLight, AppColors.pink], center: Alignment(-0.3, -0.3)),
                                    boxShadow: [BoxShadow(color: AppColors.pink.withValues(alpha: 0.6), blurRadius: 30)],
                                  ),
                                  child: const Center(child: Text('💖', style: TextStyle(fontSize: 34))),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 10,
                              child: BreatheAnimation(
                                delay: const Duration(milliseconds: 500),
                                child: Container(
                                  width: 80, height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const RadialGradient(colors: [AppColors.lavender, AppColors.purple], center: Alignment(-0.3, -0.3)),
                                    boxShadow: [BoxShadow(color: AppColors.purple.withValues(alpha: 0.6), blurRadius: 30)],
                                  ),
                                  child: const Center(child: Text('💜', style: TextStyle(fontSize: 34))),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Invite your partner', style: AppTextStyles.h1.copyWith(fontSize: 30)),
                      const SizedBox(height: 12),
                      Text(
                        'Share this code with the one you love.\nIt expires in 24 hours.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMuted,
                      ),
                      const SizedBox(height: 40),
                      // Code box + share button
                      BlocBuilder<PairingBloc, PairingState>(
                        builder: (context, state) {
                          final code = state is CodeGenerated ? state.code :
                              (state is PairingLoading ? '···' : '----');
                          final hasCode = state is CodeGenerated;
                          return Column(
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(36),
                                decoration: BoxDecoration(
                                  color: AppColors.glass,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: AppColors.pink.withValues(alpha: 0.4)),
                                ),
                                child: Column(
                                  children: [
                                    Text('YOUR INVITE CODE', style: AppTextStyles.labelCaps),
                                    const SizedBox(height: 12),
                                    ShaderMask(
                                      shaderCallback: (b) => AppGradients.gradientText.createShader(b),
                                      child: Text(code, style: AppTextStyles.inviteCode),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              GlowButton(
                                label: 'Share Code ↗',
                                onTap: hasCode
                                    ? () => Share.share(
                                        'Join me on Usync! 💖\n\nEnter this code: $code\n\nDownload the app and let\'s connect.',
                                      )
                                    : null,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      UsyncOutlineButton(
                        label: 'I have a code instead →',
                        onTap: () => context.go(RouteNames.pairJoin),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// closes _PairInviteBody
