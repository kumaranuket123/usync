import 'dart:async';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/game_content.dart';
import '../../../../core/crypto/content_cipher.dart';
import '../../../../domain/entities/game_answer.dart';
import '../../../../domain/entities/game_session.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_game_repository.dart';

sealed class WouldYouRatherEvent {}

class WouldYouRatherOpened extends WouldYouRatherEvent {
  WouldYouRatherOpened({required this.coupleId, required this.userId});
  final String coupleId, userId;
}

class _SessionChanged extends WouldYouRatherEvent {
  _SessionChanged(this.session);
  final GameSession? session;
}

class WouldYouRatherStarted extends WouldYouRatherEvent {}

/// [choice] is `A` or `B`.
class WouldYouRatherPicked extends WouldYouRatherEvent {
  WouldYouRatherPicked(this.choice);
  final String choice;
}

class WouldYouRatherEnded extends WouldYouRatherEvent {}

class WouldYouRatherState extends Equatable {
  const WouldYouRatherState({this.loading = true, this.session, this.answers = const [], this.userId = '', this.busy = false, this.error});

  final bool             loading;
  final GameSession?     session;
  final List<GameAnswer> answers;
  final String           userId;
  final bool             busy;
  final String?          error;

  /// Question indexes (into [wouldYouRatherQuestions]) for each round, in order.
  List<int> get deck => [for (final i in (session?.state['deck'] as List? ?? const [])) i as int];
  int       get rounds => deck.length;

  String? _pick(String user, int round) {
    for (final a in answers) {
      if (a.round == round && a.userId == user) return a.pick;
    }
    return null;
  }

  bool answered(String user, int round) => answers.any((a) => a.round == round && a.userId == user);

  String? myPick(int round) => _pick(userId, round);

  /// The partner's pick; the server only returns it once this user has answered the round.
  String? partnerPick(int round) {
    for (final a in answers) {
      if (a.round == round && a.userId != userId) return a.pick;
    }
    return null;
  }

  bool partnerAnswered(int round) => answers.any((a) => a.round == round && a.userId != userId);

  /// First round this user has not answered, or null when they are through.
  int? get currentRound {
    for (var r = 0; r < rounds; r++) {
      if (!answered(userId, r)) return r;
    }
    return null;
  }

  int get myCount      => [for (var r = 0; r < rounds; r++) if (answered(userId, r)) r].length;
  int get partnerCount => [for (var r = 0; r < rounds; r++) if (partnerAnswered(r)) r].length;

  /// Rounds where both picked the same option.
  int get matches => [for (var r = 0; r < rounds; r++) if (myPick(r) != null && myPick(r) == partnerPick(r)) r].length;

  @override
  List<Object?> get props => [loading, session, answers, userId, busy, error];
}

class WouldYouRatherBloc extends Bloc<WouldYouRatherEvent, WouldYouRatherState> {
  WouldYouRatherBloc({required this.gameRepository, required this.coupleRepository, this.roundCount = 10, Random? random})
      : _random = random ?? Random(),
        super(const WouldYouRatherState()) {
    on<WouldYouRatherOpened>(_onOpened);
    on<_SessionChanged>(_onSessionChanged);
    on<WouldYouRatherStarted>(_onStarted);
    on<WouldYouRatherPicked>(_onPicked);
    on<WouldYouRatherEnded>(_onEnded);
  }

  final IGameRepository   gameRepository;
  final ICoupleRepository coupleRepository;
  final int               roundCount;
  final Random            _random;
  String _coupleId = '', _userId = '';
  StreamSubscription<List<GameSession>>? _sub;
  int _latest = 0;

  Future<void> _onOpened(WouldYouRatherOpened e, Emitter<WouldYouRatherState> emit) async {
    _coupleId = e.coupleId; _userId = e.userId;
    await _sub?.cancel();
    _sub = gameRepository.watchSessions(_coupleId).listen(
      (all) {
        if (isClosed) return;
        final mine = all.where((s) => s.type == GameType.wouldYouRather).toList();
        // The running game wins over finished ones; the list is newest first.
        add(_SessionChanged(mine.where((s) => s.isActive).firstOrNull ?? mine.firstOrNull));
      },
      onError: (_) {},
    );
  }

  Future<void> _onSessionChanged(_SessionChanged e, Emitter<WouldYouRatherState> emit) async {
    final s = e.session;
    if (s == null) {
      emit(WouldYouRatherState(loading: false, userId: _userId));
      return;
    }
    // A new game starts clean; the same game keeps its answers on screen while they are refreshed.
    final same = state.session?.id == s.id;
    final ticket = ++_latest;
    emit(WouldYouRatherState(loading: false, session: s, answers: same ? state.answers : const [], userId: _userId));
    await _refresh(s, ticket, emit);
  }

  Future<void> _refresh(GameSession s, int ticket, Emitter<WouldYouRatherState> emit) async {
    try {
      final answers = await gameRepository.getAnswers(s);
      if (ticket != _latest || isClosed) return; // a newer change has been handled meanwhile
      emit(WouldYouRatherState(loading: false, session: s, answers: answers, userId: _userId));
      final done = state;
      // Once both are through every round the game is over; either phone can record that.
      if (s.isActive && done.rounds > 0 && done.myCount == done.rounds && done.partnerCount == done.rounds) {
        await gameRepository.finish(s.id);
      }
    } catch (_) {
      // Offline: keep what is on screen; the next change tries again.
    }
  }

  Future<void> _onStarted(WouldYouRatherStarted _, Emitter<WouldYouRatherState> emit) async {
    if (state.busy) return;
    final deck = List.generate(wouldYouRatherQuestions.length, (i) => i)..shuffle(_random);
    emit(WouldYouRatherState(loading: false, session: state.session, answers: state.answers, userId: _userId, busy: true));
    try {
      await gameRepository.start(
        coupleId: _coupleId, userId: _userId, type: GameType.wouldYouRather,
        state: {'deck': deck.take(roundCount).toList()},
      );
      emit(WouldYouRatherState(loading: false, session: state.session, answers: state.answers, userId: _userId));
    } catch (_) {
      emit(WouldYouRatherState(loading: false, session: state.session, answers: state.answers, userId: _userId, error: 'Could not start the game. Check your connection.'));
    }
  }

  Future<void> _onPicked(WouldYouRatherPicked e, Emitter<WouldYouRatherState> emit) async {
    final s = state.session;
    final round = state.currentRound;
    if (s == null || !s.isActive || round == null || state.busy) return;
    final last = state.myCount == state.rounds - 1;
    emit(WouldYouRatherState(loading: false, session: s, answers: state.answers, userId: _userId, busy: true));
    try {
      await gameRepository.submitAnswer(
        session: s, userId: _userId, round: round, content: {'pick': e.choice}, notify: last,
      );
      final ticket = ++_latest;
      emit(WouldYouRatherState(loading: false, session: s, answers: state.answers, userId: _userId));
      await _refresh(s, ticket, emit);
    } on EncryptionNotReady catch (err) {
      emit(WouldYouRatherState(loading: false, session: s, answers: state.answers, userId: _userId, error: err.message));
    } catch (_) {
      emit(WouldYouRatherState(loading: false, session: s, answers: state.answers, userId: _userId, error: 'Could not send your answer. Check your connection.'));
    }
  }

  Future<void> _onEnded(WouldYouRatherEnded _, Emitter<WouldYouRatherState> emit) async {
    final s = state.session;
    if (s == null || !s.isActive) return;
    try {
      await gameRepository.finish(s.id);
    } catch (_) {
      emit(WouldYouRatherState(loading: false, session: s, answers: state.answers, userId: _userId, error: 'Could not end the game. Check your connection.'));
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
