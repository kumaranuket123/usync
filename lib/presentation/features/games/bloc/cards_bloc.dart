import 'dart:async';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/game_content.dart';
import '../../../../domain/entities/game_session.dart';
import '../../../../domain/repositories/i_game_repository.dart';

sealed class CardsEvent {}

class CardsOpened extends CardsEvent {
  CardsOpened({required this.coupleId, required this.userId});
  final String coupleId, userId;
}

class _SessionChanged extends CardsEvent {
  _SessionChanged(this.session);
  final GameSession? session;
}

class CardsStarted extends CardsEvent {}

/// Turns the shared deck to the next card; on the last card it ends the game.
class CardsNext extends CardsEvent {}

class CardsEnded extends CardsEvent {}

class CardsState extends Equatable {
  const CardsState({this.loading = true, this.session, this.busy = false, this.error});

  final bool         loading;
  final GameSession? session;
  final bool         busy;
  final String?      error;

  /// Card indexes (into [conversationCards]) in the order they are turned.
  List<int> get deck => [for (final i in (session?.state['deck'] as List? ?? const [])) i as int];
  int       get position => (session?.state['pos'] as int?) ?? 0;
  bool      get isLast   => position >= deck.length - 1;

  ConversationCard? get card {
    final d = deck;
    return position < d.length ? conversationCards[d[position]] : null;
  }

  @override
  List<Object?> get props => [loading, session, busy, error];
}

class CardsBloc extends Bloc<CardsEvent, CardsState> {
  CardsBloc({required this.gameRepository, this.cardCount = 15, Random? random})
      : _random = random ?? Random(),
        super(const CardsState()) {
    on<CardsOpened>(_onOpened);
    on<_SessionChanged>((e, emit) => emit(CardsState(loading: false, session: e.session)));
    on<CardsStarted>(_onStarted);
    on<CardsNext>(_onNext);
    on<CardsEnded>(_onEnded);
  }

  final IGameRepository gameRepository;
  final int             cardCount;
  final Random          _random;
  String _coupleId = '', _userId = '';
  StreamSubscription<List<GameSession>>? _sub;

  Future<void> _onOpened(CardsOpened e, Emitter<CardsState> emit) async {
    _coupleId = e.coupleId; _userId = e.userId;
    await _sub?.cancel();
    _sub = gameRepository.watchSessions(_coupleId).listen(
      (all) {
        if (isClosed) return;
        final mine = all.where((s) => s.type == GameType.cards).toList();
        // The running game wins over finished ones; the list is newest first.
        add(_SessionChanged(mine.where((s) => s.isActive).firstOrNull ?? mine.firstOrNull));
      },
      onError: (_) {},
    );
  }

  Future<void> _onStarted(CardsStarted _, Emitter<CardsState> emit) async {
    if (state.busy) return;
    final deck = List.generate(conversationCards.length, (i) => i)..shuffle(_random);
    emit(CardsState(loading: false, session: state.session, busy: true));
    try {
      await gameRepository.start(
        coupleId: _coupleId, userId: _userId, type: GameType.cards,
        state: {'deck': deck.take(cardCount).toList(), 'pos': 0},
      );
      emit(CardsState(loading: false, session: state.session));
    } catch (_) {
      emit(CardsState(loading: false, session: state.session, error: 'Could not start the game. Check your connection.'));
    }
  }

  Future<void> _onNext(CardsNext _, Emitter<CardsState> emit) async {
    final s = state.session;
    if (s == null || !s.isActive || state.busy) return;
    emit(CardsState(loading: false, session: s, busy: true));
    try {
      if (state.isLast) {
        await gameRepository.finish(s.id);
      } else {
        await gameRepository.updateState(session: s, state: {...s.state, 'pos': state.position + 1});
      }
      emit(CardsState(loading: false, session: state.session));
    } catch (_) {
      // Usually the partner turned the card at the same moment; the stream brings the real state.
      emit(CardsState(loading: false, session: state.session, error: 'That did not go through. Try again.'));
    }
  }

  Future<void> _onEnded(CardsEnded _, Emitter<CardsState> emit) async {
    final s = state.session;
    if (s == null || !s.isActive) return;
    try {
      await gameRepository.finish(s.id);
    } catch (_) {
      emit(CardsState(loading: false, session: s, error: 'Could not end the game. Check your connection.'));
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
