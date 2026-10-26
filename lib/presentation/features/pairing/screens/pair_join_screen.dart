import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/animations/breathe_animation.dart';
import '../../../shared/widgets/centered_scroll.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../../../core/di/injection.dart';
import '../bloc/pairing_bloc.dart';

class PairJoinScreen extends StatelessWidget {
  const PairJoinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<PairingBloc>(),
      child: const _PairJoinBody(),
    );
  }
}

class _PairJoinBody extends StatefulWidget {
  const _PairJoinBody();
  @override
  State<_PairJoinBody> createState() => _PairJoinBodyState();
}

class _PairJoinBodyState extends State<_PairJoinBody> {
  final _ctrls = List.generate(4, (_) => TextEditingController());
  final _foci  = List.generate(4, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final f in _foci) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _ctrls.map((c) => c.text).join();

  @override
  Widget build(BuildContext context) {
    return BlocListener<PairingBloc, PairingState>(
      listener: (context, state) {
        if (state is PairingSuccess) context.go(RouteNames.pairSuccess);
        if (state is PairingError) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
      },
      child: Scaffold(
        backgroundColor: AppColors.bg1,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: NeonBackButton(onTap: () => context.go(RouteNames.pairInvite)),
                ),
              ),
              Expanded(
                child: CenteredScroll(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BreatheAnimation(
                          child: const Text('🔑', style: TextStyle(fontSize: 60)),
                        ),
                        const SizedBox(height: 24),
                        Text("Enter partner's code", style: AppTextStyles.h1.copyWith(fontSize: 30)),
                        const SizedBox(height: 12),
                        Text("Type the invite code\nyour partner shared with you.",
                            textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (i) {
                            return Container(
                              width: 56, height: 66,
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              child: TextField(
                                controller:  _ctrls[i],
                                focusNode:   _foci[i],
                                maxLength:   1,
                                textAlign:   TextAlign.center,
                                textCapitalization: TextCapitalization.characters,
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                                decoration: InputDecoration(
                                  counterText: '',
                                  // The app theme pads inputs 20px each side, which leaves a 56px box
                                  // too little room for a letter (it was clipped away).
                                  contentPadding: EdgeInsets.zero,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: AppColors.pink.withValues(alpha: 0.6), width: 1.5),
                                  ),
                                  fillColor: AppColors.pink.withValues(alpha: 0.08),
                                ),
                                onChanged: (val) {
                                  if (val.isNotEmpty && i < 3) {
                                    _foci[i + 1].requestFocus();
                                  }
                                },
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 24),
                        BlocBuilder<PairingBloc, PairingState>(
                          builder: (context, state) => GlowButton(
                            label: 'Connect ✦',
                            isLoading: state is PairingLoading,
                            onTap: () => context.read<PairingBloc>().add(
                              JoinWithCodeRequested(
                                code:   _code.toUpperCase(),
                                userId: Supabase.instance.client.auth.currentUser!.id,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
