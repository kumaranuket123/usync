import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/constants/game_content.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_snack_bar.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/would_you_rather_bloc.dart';

class WouldYouRatherScreen extends StatelessWidget {
  const WouldYouRatherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    return BlocProvider(
      create: (_) => GetIt.I<WouldYouRatherBloc>()
        ..add(WouldYouRatherOpened(coupleId: user?.coupleId ?? '', userId: user?.id ?? '')),
      child: BlocListener<WouldYouRatherBloc, WouldYouRatherState>(
        listenWhen: (_, b) => b.error != null,
        listener: (context, state) =>
            ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: Text(state.error!))),
        child: const _Body(),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: BlocBuilder<WouldYouRatherBloc, WouldYouRatherState>(
          builder: (context, state) {
            final s = state.session;
            final active = s?.isActive ?? false;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                  child: Row(
                    children: [
                      const NeonBackButton(),
                      const SizedBox(width: 14),
                      Expanded(child: Text('Would you rather', style: AppTextStyles.h2.copyWith(fontSize: 22))),
                    ],
                  ),
                ),
                Expanded(
                  child: state.loading
                      ? const Center(child: LoadingDots())
                      : s == null
                          ? const _Intro()
                          : _Game(state: state),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: active
                      ? TextButton(
                          onPressed: () => context.read<WouldYouRatherBloc>().add(WouldYouRatherEnded()),
                          child: const Text('End game', style: TextStyle(color: AppColors.textMuted)),
                        )
                      : GlowButton(
                          label: s == null ? 'Start a game' : 'Play again',
                          isLoading: state.busy,
                          onTap: state.loading ? null : () => context.read<WouldYouRatherBloc>().add(WouldYouRatherStarted()),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🤔', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('Pick one of two, then see what your partner picked', style: AppTextStyles.h3, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Answers stay hidden until you have both answered a question.', style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _Game extends StatelessWidget {
  const _Game({required this.state});
  final WouldYouRatherState state;

  @override
  Widget build(BuildContext context) {
    final round = state.currentRound;
    final finished = !(state.session?.isActive ?? false);
    final answered = [for (var r = 0; r < state.rounds; r++) if (state.answered(state.userId, r)) r];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      children: [
        if (finished)
          _Summary(state: state)
        else if (round != null)
          _Question(state: state, round: round)
        else
          _Waiting(state: state),
        if (answered.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('YOUR ANSWERS', style: AppTextStyles.labelCaps),
          const SizedBox(height: 10),
          for (final r in answered.reversed) _ResultTile(state: state, round: r),
        ],
      ],
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.state, required this.round});
  final WouldYouRatherState state;
  final int round;

  @override
  Widget build(BuildContext context) {
    final q = wouldYouRatherQuestions[state.deck[round]];
    Widget option(String choice, String text, Color color) => GestureDetector(
          onTap: state.busy ? null : () => context.read<WouldYouRatherBloc>().add(WouldYouRatherPicked(choice)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color),
            ),
            child: Text(text, style: AppTextStyles.bodyLarge, textAlign: TextAlign.center),
          ),
        );
    return Column(
      children: [
        Text('Question ${round + 1} of ${state.rounds}', style: AppTextStyles.label),
        const SizedBox(height: 4),
        Text('Would you rather…', style: AppTextStyles.h3),
        const SizedBox(height: 16),
        option('A', q.a, AppColors.pink),
        const SizedBox(height: 10),
        Text('or', style: AppTextStyles.label),
        const SizedBox(height: 10),
        option('B', q.b, AppColors.cyan),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.state});
  final WouldYouRatherState state;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Text('⏳', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text("You're all done!", style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text('Your partner has answered ${state.partnerCount} of ${state.rounds}. Come back to see how you matched.',
              style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
        ],
      );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state});
  final WouldYouRatherState state;

  @override
  Widget build(BuildContext context) {
    final complete = state.myCount == state.rounds && state.partnerCount == state.rounds;
    return Column(
      children: [
        const Text('💞', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 8),
        Text(complete ? 'You matched on ${state.matches} of ${state.rounds}' : 'Game ended', style: AppTextStyles.h3),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.state, required this.round});
  final WouldYouRatherState state;
  final int round;

  @override
  Widget build(BuildContext context) {
    final q = wouldYouRatherQuestions[state.deck[round]];
    String label(String? pick) => switch (pick) { 'A' => q.a, 'B' => q.b, _ => 'Unreadable' };
    final mine = state.myPick(round);
    final partner = state.partnerPick(round);
    final waiting = !state.partnerAnswered(round);
    final match = !waiting && mine != null && mine == partner;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: match ? AppColors.online : AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You: ${label(mine)}', style: AppTextStyles.body),
          const SizedBox(height: 4),
          Text(waiting ? 'Partner: waiting…' : 'Partner: ${label(partner)}', style: AppTextStyles.bodyMuted),
          if (match) ...[
            const SizedBox(height: 4),
            Text('You matched 💞', style: AppTextStyles.label.copyWith(color: AppColors.online)),
          ],
        ],
      ),
    );
  }
}
