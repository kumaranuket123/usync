import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_snack_bar.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/tic_tac_toe_bloc.dart';

class TicTacToeScreen extends StatelessWidget {
  const TicTacToeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    return BlocProvider(
      create: (_) => GetIt.I<TicTacToeBloc>()
        ..add(TicTacToeOpened(coupleId: user?.coupleId ?? '', userId: user?.id ?? '')),
      child: BlocListener<TicTacToeBloc, TicTacToeState>(
        listenWhen: (_, b) => b.error != null,
        listener: (context, state) =>
            ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: Text(state.error!))),
        child: _PresenceWatcher(child: _TicTacToeBody(userId: user?.id ?? '')),
      ),
    );
  }
}

/// Tells the bloc when the app leaves or returns to the screen, so the partner is only treated as
/// "looking at the board" while they really are.
class _PresenceWatcher extends StatefulWidget {
  const _PresenceWatcher({required this.child});
  final Widget child;

  @override
  State<_PresenceWatcher> createState() => _PresenceWatcherState();
}

class _PresenceWatcherState extends State<_PresenceWatcher> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bloc = context.read<TicTacToeBloc>();
    if (state == AppLifecycleState.resumed) bloc.add(TicTacToeShown());
    if (state == AppLifecycleState.paused) bloc.add(TicTacToeHidden());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TicTacToeBody extends StatelessWidget {
  const _TicTacToeBody({required this.userId});
  final String userId;

  String _headline(TicTacToeState state) {
    final s = state.session;
    if (s == null) return 'Challenge your partner to a game';
    final result = state.outcome;
    if (!s.isActive) {
      if (result == 'draw') return "It's a draw 🤝";
      if (result == null) return 'Game ended';
      return result == TicTacToeBloc.markOf(s, userId) ? 'You won! 🎉' : 'Your partner won';
    }
    return s.isMyTurn(userId) ? 'Your turn' : "Waiting for your partner…";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: BlocBuilder<TicTacToeBloc, TicTacToeState>(
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
                      Expanded(child: Text('Tic-Tac-Toe', style: AppTextStyles.h2.copyWith(fontSize: 22))),
                    ],
                  ),
                ),
                Expanded(
                  child: state.loading
                      ? const Center(child: LoadingDots())
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_headline(state), style: AppTextStyles.h3),
                              if (s != null) ...[
                                const SizedBox(height: 4),
                                Text('You are ${TicTacToeBloc.markOf(s, userId)}', style: AppTextStyles.label),
                                const SizedBox(height: 24),
                                _Board(
                                  board: state.board,
                                  enabled: active && s.isMyTurn(userId) && !state.busy,
                                  onTap: (i) => context.read<TicTacToeBloc>().add(TicTacToeCellTapped(i)),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: active
                      ? TextButton(
                          onPressed: () => context.read<TicTacToeBloc>().add(TicTacToeEnded()),
                          child: const Text('End game', style: TextStyle(color: AppColors.textMuted)),
                        )
                      : GlowButton(
                          label: s == null ? 'Start a game' : 'Play again',
                          isLoading: state.busy,
                          onTap: state.loading ? null : () => context.read<TicTacToeBloc>().add(TicTacToeStarted()),
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

class _Board extends StatelessWidget {
  const _Board({required this.board, required this.enabled, required this.onTap});

  final String            board;
  final bool              enabled;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 9; i++)
            GestureDetector(
              onTap: enabled && board[i] == ' ' ? () => onTap(i) : null,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.glass,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Text(
                  board[i] == ' ' ? '' : board[i],
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: board[i] == 'X' ? AppColors.pink : AppColors.cyan,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
