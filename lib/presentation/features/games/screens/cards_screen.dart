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
import '../bloc/cards_bloc.dart';

class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    return BlocProvider(
      create: (_) => GetIt.I<CardsBloc>()..add(CardsOpened(coupleId: user?.coupleId ?? '', userId: user?.id ?? '')),
      child: BlocListener<CardsBloc, CardsState>(
        listenWhen: (_, b) => b.error != null,
        listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: Text(state.error!))),
        child: const _Body(),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  Color _color(CardKind k) => switch (k) {
    CardKind.talk  => AppColors.cyan,
    CardKind.truth => AppColors.lavender,
    CardKind.dare  => AppColors.pink,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: BlocBuilder<CardsBloc, CardsState>(
          builder: (context, state) {
            final s = state.session;
            final active = s?.isActive ?? false;
            final card = active ? state.card : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                  child: Row(
                    children: [
                      const NeonBackButton(),
                      const SizedBox(width: 14),
                      Expanded(child: Text('Conversation cards', style: AppTextStyles.h2.copyWith(fontSize: 22))),
                    ],
                  ),
                ),
                Expanded(
                  child: state.loading
                      ? const Center(child: LoadingDots())
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Center(
                            child: card == null
                                ? _Message(finished: s != null)
                                : _CardView(card: card, color: _color(card.kind), n: state.position + 1, total: state.deck.length),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: Column(
                    children: [
                      GlowButton(
                        label: !active ? (s == null ? 'Start a game' : 'Play again') : state.isLast ? 'Finish' : 'Next card',
                        isLoading: state.busy,
                        onTap: state.loading
                            ? null
                            : () => context.read<CardsBloc>().add(active ? CardsNext() : CardsStarted()),
                      ),
                      if (active)
                        TextButton(
                          onPressed: () => context.read<CardsBloc>().add(CardsEnded()),
                          child: const Text('End game', style: TextStyle(color: AppColors.textMuted)),
                        ),
                    ],
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

class _Message extends StatelessWidget {
  const _Message({required this.finished});
  final bool finished;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(finished ? '💞' : '🃏', style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(finished ? 'That was the last card' : 'Turn cards together', style: AppTextStyles.h3, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            finished
                ? 'Hope it sparked some good talk.'
                : 'You both see the same card. Talk about it, answer honestly, or take the dare, then turn to the next.',
            style: AppTextStyles.bodyMuted,
            textAlign: TextAlign.center,
          ),
        ],
      );
}

class _CardView extends StatelessWidget {
  const _CardView({required this.card, required this.color, required this.n, required this.total});
  final ConversationCard card;
  final Color color;
  final int n, total;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${card.kind.emoji}  ${card.kind.label.toUpperCase()}', style: AppTextStyles.labelCaps.copyWith(color: color)),
            const SizedBox(height: 18),
            Text(card.text, style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            Text('Card $n of $total', style: AppTextStyles.label),
          ],
        ),
      );
}
