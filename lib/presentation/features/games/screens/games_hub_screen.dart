import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/entities/game_session.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/games_bloc.dart';

class GamesHubScreen extends StatelessWidget {
  const GamesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    return BlocProvider(
      create: (_) => GetIt.I<GamesBloc>()..add(GamesOpened(coupleId: user?.coupleId ?? '', userId: user?.id ?? '')),
      child: const _GamesBody(),
    );
  }
}

class _GamesBody extends StatelessWidget {
  const _GamesBody();

  String _route(GameType t) => switch (t) {
    GameType.ticTacToe => RouteNames.ticTacToe,
    GameType.wouldYouRather => RouteNames.wouldYouRather,
    GameType.quiz => RouteNames.quiz,
    GameType.cards => RouteNames.cards,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: BlocBuilder<GamesBloc, GamesState>(
          builder: (context, state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                child: Row(
                  children: [
                    const NeonBackButton(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Couple games', style: AppTextStyles.h2.copyWith(fontSize: 22)),
                          Text(
                            state.waitingForMe == 0
                                ? 'Spend some time together'
                                : '${state.waitingForMe} waiting for your move',
                            style: AppTextStyles.label,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  children: [
                    for (final type in GameType.values) ...[
                      _GameCard(
                        type: type,
                        session: state.active(type),
                        userId: state.userId,
                        onTap: () => context.push(_route(type)),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.type, required this.session, required this.userId, required this.onTap});

  final GameType     type;
  final GameSession? session;
  final String       userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final myTurn = session?.isMyTurn(userId) ?? false;
    final status = session == null
        ? 'Start a game'
        : !type.isTurnBased
            ? 'In progress'
            : myTurn ? 'Your turn' : 'Waiting for your partner';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: myTurn ? AppColors.pink : AppColors.glassBorder),
        ),
        child: Row(
          children: [
            Text(type.emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.title, style: AppTextStyles.h4),
                  const SizedBox(height: 2),
                  Text(status, style: AppTextStyles.label.copyWith(color: myTurn ? AppColors.pink : null)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
