import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/game_session.dart';
import '../../../../domain/repositories/i_game_repository.dart';

sealed class GamesEvent {}

class GamesOpened extends GamesEvent {
  GamesOpened({required this.coupleId, required this.userId});
  final String coupleId, userId;
}

class _SessionsChanged extends GamesEvent {
  _SessionsChanged(this.sessions);
  final List<GameSession> sessions;
}

class GamesState extends Equatable {
  const GamesState({this.sessions = const [], this.userId = ''});

  /// Games still running; at most one per kind.
  final List<GameSession> sessions;
  final String            userId;

  GameSession? active(GameType type) {
    for (final s in sessions) {
      if (s.type == type) return s;
    }
    return null;
  }

  /// Number of running games waiting for this user.
  int get waitingForMe => sessions.where((s) => s.isMyTurn(userId)).length;

  @override
  List<Object?> get props => [sessions, userId];
}

/// The games hub: which games are running and whose turn each one is.
class GamesBloc extends Bloc<GamesEvent, GamesState> {
  GamesBloc({required this.gameRepository}) : super(const GamesState()) {
    on<GamesOpened>(_onOpened);
    on<_SessionsChanged>((e, emit) =>
        emit(GamesState(sessions: e.sessions.where((s) => s.isActive).toList(), userId: state.userId)));
  }

  final IGameRepository gameRepository;
  StreamSubscription<List<GameSession>>? _sub;

  Future<void> _onOpened(GamesOpened e, Emitter<GamesState> emit) async {
    emit(GamesState(userId: e.userId));
    await _sub?.cancel();
    _sub = gameRepository.watchSessions(e.coupleId).listen(
      (s) { if (!isClosed) add(_SessionsChanged(s)); },
      onError: (_) {},
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
