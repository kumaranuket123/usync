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
import '../bloc/quiz_bloc.dart';

class QuizScreen extends StatelessWidget {
  const QuizScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    return BlocProvider(
      create: (_) => GetIt.I<QuizBloc>()..add(QuizOpened(coupleId: user?.coupleId ?? '', userId: user?.id ?? '')),
      child: BlocListener<QuizBloc, QuizState>(
        listenWhen: (_, b) => b.error != null,
        listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: Text(state.error!))),
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
        child: BlocBuilder<QuizBloc, QuizState>(
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
                      Expanded(child: Text('How well do you know me?', style: AppTextStyles.h2.copyWith(fontSize: 20))),
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
                          onPressed: () => context.read<QuizBloc>().add(QuizEnded()),
                          child: const Text('End game', style: TextStyle(color: AppColors.textMuted)),
                        )
                      : GlowButton(
                          label: s == null ? 'Start a game' : 'Play again',
                          isLoading: state.busy,
                          onTap: state.loading ? null : () => context.read<QuizBloc>().add(QuizStarted()),
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
              const Text('🧠', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('Answer for yourself, then guess your partner', style: AppTextStyles.h3, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Each question has two steps. Your partner\'s answers stay hidden until you have answered the question too.',
                  style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _Game extends StatelessWidget {
  const _Game({required this.state});
  final QuizState state;

  @override
  Widget build(BuildContext context) {
    final round = state.currentRound;
    final finished = !(state.session?.isActive ?? false);
    final answered = state.mine.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      children: [
        if (finished)
          _Scores(state: state)
        else if (round != null)
          _Round(state: state, round: round)
        else
          _Waiting(state: state),
        if (answered.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('YOUR ROUNDS', style: AppTextStyles.labelCaps),
          const SizedBox(height: 10),
          for (final r in answered.reversed) _ResultTile(state: state, round: r),
        ],
      ],
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.state, required this.round});
  final QuizState state;
  final int round;

  @override
  Widget build(BuildContext context) {
    final q = quizQuestions[state.deck[round]];
    final guessing = state.pendingSelf != null;
    final bloc = context.read<QuizBloc>();
    Widget option(int i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: state.busy ? null : () => bloc.add(guessing ? QuizGuessed(i) : QuizSelfPicked(i)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.glass,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: guessing ? AppColors.cyan : AppColors.pink),
              ),
              child: Text(q.options[i], style: AppTextStyles.body, textAlign: TextAlign.center),
            ),
          ),
        );
    return Column(
      children: [
        Text('Question ${round + 1} of ${state.rounds}', style: AppTextStyles.label),
        const SizedBox(height: 4),
        Text(q.topic, style: AppTextStyles.h3, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(guessing ? "Now guess your partner's answer" : 'What is your answer?', style: AppTextStyles.bodyMuted),
        const SizedBox(height: 16),
        for (var i = 0; i < q.options.length; i++) option(i),
        if (guessing)
          TextButton(
            onPressed: state.busy ? null : () => bloc.add(QuizSelfCleared()),
            child: const Text('Change my answer', style: TextStyle(color: AppColors.textMuted)),
          ),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.state});
  final QuizState state;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Text('⏳', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text("You're all done!", style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text('Your partner has answered ${state.partnerCount} of ${state.rounds}. Come back to see your scores.',
              style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
        ],
      );
}

class _Scores extends StatelessWidget {
  const _Scores({required this.state});
  final QuizState state;

  @override
  Widget build(BuildContext context) {
    final complete = state.myCount == state.rounds && state.partnerCount == state.rounds;
    return Column(
      children: [
        const Text('💞', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 8),
        Text(complete ? 'Scores' : 'Game ended', style: AppTextStyles.h3),
        if (complete) ...[
          const SizedBox(height: 6),
          Text('You knew ${state.myScore} of ${state.rounds} of your partner\'s answers', style: AppTextStyles.body),
          Text('They knew ${state.partnerScore} of ${state.rounds} of yours', style: AppTextStyles.body),
        ],
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.state, required this.round});
  final QuizState state;
  final int round;

  @override
  Widget build(BuildContext context) {
    final q = quizQuestions[state.deck[round]];
    final mine = state.mine[round]!;
    final theirs = state.partner[round];
    final right = theirs != null && theirs.self == mine.guess;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: right ? AppColors.online : AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q.topic, style: AppTextStyles.label),
          const SizedBox(height: 4),
          Text('You: ${q.options[mine.self]}', style: AppTextStyles.body),
          Text('You guessed: ${q.options[mine.guess]}', style: AppTextStyles.bodyMuted),
          const SizedBox(height: 4),
          if (theirs == null)
            Text('Partner: waiting…', style: AppTextStyles.bodyMuted)
          else ...[
            Text('Partner: ${q.options[theirs.self]}', style: AppTextStyles.body),
            Text('They guessed: ${q.options[theirs.guess]}', style: AppTextStyles.bodyMuted),
            if (right) Text('You knew it 💞', style: AppTextStyles.label.copyWith(color: AppColors.online)),
          ],
        ],
      ),
    );
  }
}
