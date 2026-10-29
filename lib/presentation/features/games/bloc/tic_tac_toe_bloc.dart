import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/game_session.dart';
import '../../../../domain/games/tic_tac_toe.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_game_repository.dart';

sealed class TicTacToeEvent {}

class TicTacToeOpened extends TicTacToeEvent {
  TicTacToeOpened({required this.coupleId, required this.userId});
  final String coupleId, userId;
}

class _SessionChanged extends TicTacToeEvent {
  _SessionChanged(this.session);
  final GameSession? session;
}

/// The screen is in front again (app resumed): announce it, so a move needs no push.
class TicTacToeShown extends TicTacToeEvent {}

/// The app went to the background: the partner's moves should push again.
class TicTacToeHidden extends TicTacToeEvent {}

class TicTacToeStarted extends TicTacToeEvent {}

class TicTacToeCellTapped extends TicTacToeEvent {
  TicTacToeCellTapped(this.cell);
  final int cell;
}

/// Ends the game for both partners, finished or not.
class TicTacToeEnded extends TicTacToeEvent {}

class TicTacToeState extends Equatable {
  const TicTacToeState({this.loading = true, this.session, this.busy = false, this.error});

  final bool         loading;
  /// The running game, or the last finished one (shown with its result); null when none exists.
  final GameSession? session;
  final bool         busy;
  final String?      error;

  String get board => (session?.state['board'] as String?) ?? TicTacToe.empty;

  /// `X`, `O` or `draw` once the game is over.
  String? get outcome => TicTacToe.outcome(board);

  @override
  List<Object?> get props => [loading, session, busy, error];
}

class TicTacToeBloc extends Bloc<TicTacToeEvent, TicTacToeState> {
  TicTacToeBloc({required this.gameRepository, required this.coupleRepository}) : super(const TicTacToeState()) {
    on<TicTacToeOpened>(_onOpened);
    on<_SessionChanged>(_onSessionChanged);
    on<TicTacToeShown>((_, __) => _announce(true));
    on<TicTacToeHidden>((_, __) => _announce(false));
    on<TicTacToeStarted>(_onStarted);
    on<TicTacToeCellTapped>(_onCellTapped);
    on<TicTacToeEnded>(_onEnded);
  }

  final IGameRepository   gameRepository;
  final ICoupleRepository coupleRepository;
  String _coupleId = '', _userId = '', _partnerId = '';
  StreamSubscription<List<GameSession>>? _sub;

  /// Which mark a player has: the starter is X.
  static String markOf(GameSession s, String userId) => s.state['x'] == userId ? 'X' : 'O';

  Future<void> _onOpened(TicTacToeOpened e, Emitter<TicTacToeState> emit) async {
    _coupleId = e.coupleId; _userId = e.userId;
    try {
      _partnerId = (await coupleRepository.getCouple(_coupleId)).partnerIdFor(_userId);
    } catch (_) {
      // Offline with no saved copy: a game can be continued but not started until we are back online.
    }
    _announce(true);
    await _sub?.cancel();
    _sub = gameRepository.watchSessions(_coupleId).listen(
      (all) {
        if (isClosed) return;
        final mine = all.where((s) => s.type == GameType.ticTacToe).toList();
        // The running game wins over finished ones; the list is newest first.
        final pick = mine.where((s) => s.isActive).firstOrNull ?? mine.firstOrNull;
        add(_SessionChanged(pick));
      },
      onError: (_) {},
    );
  }

  /// Lets the partner know whether this user is looking at the game; failures do not matter
  /// (the worst case is one push too many).
  void _announce(bool here) {
    if (_coupleId.isEmpty || _userId.isEmpty) return;
    final done = here
        ? gameRepository.enterGame(coupleId: _coupleId, userId: _userId, type: GameType.ticTacToe)
        : gameRepository.leaveGame(coupleId: _coupleId, userId: _userId);
    done.catchError((_) {});
  }

  void _onSessionChanged(_SessionChanged e, Emitter<TicTacToeState> emit) =>
      emit(TicTacToeState(loading: false, session: e.session));

  Future<void> _onStarted(TicTacToeStarted _, Emitter<TicTacToeState> emit) async {
    if (state.busy) return;
    if (_partnerId.isEmpty) {
      emit(TicTacToeState(loading: false, session: state.session, error: 'Could not start the game. Check your connection.'));
      return;
    }
    emit(TicTacToeState(loading: false, session: state.session, busy: true));
    try {
      await gameRepository.start(
        coupleId: _coupleId, userId: _userId, type: GameType.ticTacToe,
        state: {'board': TicTacToe.empty, 'x': _userId, 'o': _partnerId},
      );
      emit(TicTacToeState(loading: false, session: state.session));
    } catch (_) {
      emit(TicTacToeState(loading: false, session: state.session, error: 'Could not start the game. Check your connection.'));
    }
  }

  Future<void> _onCellTapped(TicTacToeCellTapped e, Emitter<TicTacToeState> emit) async {
    final s = state.session;
    if (s == null || state.busy || !s.isMyTurn(_userId) || !TicTacToe.canPlay(state.board, e.cell)) return;
    final board  = TicTacToe.play(state.board, e.cell);
    final result = TicTacToe.outcome(board);
    emit(TicTacToeState(loading: false, session: s, busy: true));
    try {
      await gameRepository.makeMove(
        session: s, userId: _userId, finish: result != null,
        state: {...s.state, 'board': board, 'result': result},
      );
      emit(TicTacToeState(loading: false, session: state.session));
    } catch (_) {
      // Usually the partner's phone moved first or the game was ended; the stream brings the real state.
      emit(TicTacToeState(loading: false, session: state.session, error: 'That move did not go through. Try again.'));
    }
  }

  Future<void> _onEnded(TicTacToeEnded _, Emitter<TicTacToeState> emit) async {
    final s = state.session;
    if (s == null || !s.isActive) return;
    try {
      await gameRepository.finish(s.id);
    } catch (_) {
      emit(TicTacToeState(loading: false, session: s, error: 'Could not end the game. Check your connection.'));
    }
  }

  @override
  Future<void> close() async {
    _announce(false);
    await _sub?.cancel();
    return super.close();
  }
}
