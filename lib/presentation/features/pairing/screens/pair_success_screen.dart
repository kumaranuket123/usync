import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/encryption_state.dart';
import '../../../../domain/repositories/i_encryption_repository.dart';
import '../../../shared/widgets/centered_scroll.dart';
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
          CenteredScroll(
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
                  const SizedBox(height: 20),
                  const _SecuringLine(),
                  const SizedBox(height: 28),
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

/// "Securing your connection": the keys being set up between the two phones. It keeps looking until
/// the keys are in place (the partner's phone has to take part), and only reports; it never blocks.
class _SecuringLine extends StatefulWidget {
  const _SecuringLine();
  @override
  State<_SecuringLine> createState() => _SecuringLineState();
}

class _SecuringLineState extends State<_SecuringLine> {
  EncryptionState _state = const EncryptionState.unknown();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _check();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    // The couple was only just created, so give the app-wide user a moment to catch up.
    final next = await GetIt.I<IEncryptionRepository>().sync();
    if (!mounted) return;
    setState(() => _state = next);
    if (next.isReady) _poll?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _state.isReady;
    final text = switch (_state.phase) {
      EncryptionPhase.ready => '🔐 Your connection is secured',
      EncryptionPhase.waitingForPartner || EncryptionPhase.waitingForKey => '🔐 Securing your connection. Waiting for your partner\'s phone…',
      EncryptionPhase.needsVerification => '🔐 One last step: compare your security code with your partner',
      EncryptionPhase.partnerKeyChanged => '⚠️ Your partner\'s security code changed. Check it in Profile → Security',
      _ => '🔐 Securing your connection…',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, textAlign: TextAlign.center, style: AppTextStyles.labelSmall),
        if (ready || _state.phase == EncryptionPhase.needsVerification)
          TextButton(
            onPressed: () => context.push(RouteNames.security),
            child: Text('Compare your security code', style: AppTextStyles.link),
          ),
      ],
    );
  }
}
