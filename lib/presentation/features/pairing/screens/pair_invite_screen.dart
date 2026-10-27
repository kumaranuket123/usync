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
import '../../../shared/widgets/centered_scroll.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/outline_button.dart';
import '../../../shared/widgets/particle_field.dart';
import '../../../../core/di/injection.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/pairing_bloc.dart';
import '../../../../core/utils/app_snack_bar.dart';
import '../../../../core/utils/invite_message.dart';
import '../../settings/widgets/account_links.dart';

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
      context.read<PairingBloc>()
        ..add(GenerateCodeRequested(uid))
        ..add(WatchPartnerJoined(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PairingBloc, PairingState>(
      listener: (context, state) {
        if (state is PartnerJoined) {
          context.go(RouteNames.pairSuccess);
        } else if (state is PairingError) {
          ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: Text(state.message)));
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg1,
        body: Stack(
          children: [
            const ParticleField(count: 25),
            SafeArea(
              child: CenteredScroll(
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
                                    ? () => Share.share(inviteMessage(code))
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
                      const SizedBox(height: 4),
                      // Wrong Google account? Sign out; app.dart then sends the user to login.
                      TextButton(
                        onPressed: () => _confirmSignOut(context),
                        child: Text('Use a different account', style: AppTextStyles.bodyMuted.copyWith(fontSize: 14)),
                      ),
                      const AccountLinks(),
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

Future<void> _confirmSignOut(BuildContext context) async {
  final auth = context.read<AuthBloc>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.bg2,
      title: const Text('Sign out?', style: TextStyle(color: Colors.white)),
      content: Text('You can sign in with a different Google account.', style: AppTextStyles.bodyMuted),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign Out', style: TextStyle(color: Color(0xFFFF5050)))),
      ],
    ),
  );
  if (ok == true) auth.add(const SignOutRequested());
}

