import 'dart:async';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/game_content.dart';
import '../../../../core/crypto/content_cipher.dart';
import '../../../../domain/entities/game_answer.dart';
import '../../../../domain/entities/game_session.dart';
import '../../../../domain/games/quiz_scoring.dart';
import '../../../../domain/repositories/i_game_repository.dart';

sealed class QuizEvent {}

class QuizOpened extends QuizEvent {
  QuizOpened({required this.coupleId, required this.userId});
  final String coupleId, userId;
}

class _SessionChanged extends QuizEvent {
  _SessionChanged(this.session);
  final GameSession? session;
}

class QuizStarted extends QuizEvent {}

/// Step 1 of a round: the user's own answer (index of the option). Kept on this phone until step 2.
class QuizSelfPicked extends QuizEvent {
  QuizSelfPicked(this.option);
  final int option;
}

/// Step 2 of a round: the guess of the partner's answer. Sends both answers together.
class QuizGuessed extends QuizEvent {
  QuizGuessed(this.option);
  final int option;
}

/// Back from step 2 to step 1 of the current round.
class QuizSelfCleared extends QuizEvent {}

class QuizEnded extends QuizEvent {}

class QuizState extends Equatable {
  const QuizState({
    this.loading = true,
    this.session,
    this.answers = const [],
    this.userId = '',
    this.pendingSelf,
    this.busy = false,
    this.error,
  });

  final bool             loading;
  final GameSession?     session;
  final List<GameAnswer> answers;
  final String           userId;
  /// The user's own answer for the current round, waiting for their guess.
  final int?             pendingSelf;
  final bool             busy;
  final String?          error;

  /// Question indexes (into [quizQuestions]) for each round, in order.
  List<int> get deck   => [for (final i in (session?.state['deck'] as List? ?? const [])) i as int];
  int       get rounds => deck.length;

  Map<int, QuizEntry> _entries(bool mine) => {
        for (final a in answers)
          if ((a.userId == userId) == mine)
            if (QuizEntry.fromAnswer(a) case final e?) a.round: e,
      };

  /// What this user answered and guessed, by round.
  Map<int, QuizEntry> get mine => _entries(true);
  /// The partner's rows; the server only returns a round once this user has answered it too.
  Map<int, QuizEntry> get partner => _entries(false);

  int? get currentRound {
    final m = mine;
    for (var r = 0; r < rounds; r++) {
      if (!m.containsKey(r)) return r;
    }
    return null;
  }

  int get myCount      => mine.length;
  int get partnerCount => partner.length;

  /// How many of the partner's answers this user guessed.
  int get myScore      => QuizScoring.correctGuesses(guesser: mine, partner: partner);
  /// How many of this user's answers the partner guessed.
  int get partnerScore => QuizScoring.correctGuesses(guesser: partner, partner: mine);

  @override
  List<Object?> get props => [loading, session, answers, userId, pendingSelf, busy, error];
}

class QuizBloc extends Bloc<QuizEvent, QuizState> {
  QuizBloc({required this.gameRepository, this.roundCount = 8, Random? random})
      : _random = random ?? Random(),
        super(const QuizState()) {
    on<QuizOpened>(_onOpened);
    on<_SessionChanged>(_onSessionChanged);
    on<QuizStarted>(_onStarted);
    on<QuizSelfPicked>((e, emit) => emit(_copy(pendingSelf: e.option)));
    on<QuizSelfCleared>((e, emit) => emit(_copy()));
    on<QuizGuessed>(_onGuessed);
    on<QuizEnded>(_onEnded);
  }

  final IGameRepository gameRepository;
  final int             roundCount;
  final Random          _random;
  String _coupleId = '', _userId = '';
  StreamSubscription<List<GameSession>>? _sub;
  int _latest = 0;

  QuizState _copy({int? pendingSelf, bool busy = false, String? error, GameSession? session, List<GameAnswer>? answers}) => QuizState(
        loading: false,
        session: session ?? state.session,
        answers: answers ?? state.answers,
        userId: _userId,
        pendingSelf: pendingSelf,
        busy: busy,
        error: error,
      );

  Future<void> _onOpened(QuizOpened e, Emitter<QuizState> emit) async {
    _coupleId = e.coupleId; _userId = e.userId;
    await _sub?.cancel();
    _sub = gameRepository.watchSessions(_coupleId).listen(
      (all) {
        if (isClosed) return;
        final mine = all.where((s) => s.type == GameType.quiz).toList();
        // The running game wins over finished ones; the list is newest first.
        add(_SessionChanged(mine.where((s) => s.isActive).firstOrNull ?? mine.firstOrNull));
      },
      onError: (_) {},
    );
  }

  Future<void> _onSessionChanged(_SessionChanged e, Emitter<QuizState> emit) async {
    final s = e.session;
    if (s == null) {
      emit(QuizState(loading: false, userId: _userId));
      return;
    }
    // A new game starts clean; the same game keeps its answers on screen while they are refreshed.
    final same = state.session?.id == s.id;
    final ticket = ++_latest;
    emit(QuizState(loading: false, session: s, answers: same ? state.answers : const [], userId: _userId, pendingSelf: same ? state.pendingSelf : null));
    await _refresh(s, ticket, emit);
  }

  Future<void> _refresh(GameSession s, int ticket, Emitter<QuizState> emit) async {
    try {
      final answers = await gameRepository.getAnswers(s);
      if (ticket != _latest || isClosed) return; // a newer change has been handled meanwhile
      emit(_copy(session: s, answers: answers, pendingSelf: state.pendingSelf));
      final now = state;
      // Once both are through every round the game is over; either phone can record that.
      if (s.isActive && now.rounds > 0 && now.myCount == now.rounds && now.partnerCount == now.rounds) {
        await gameRepository.finish(s.id);
      }
    } catch (_) {
      // Offline: keep what is on screen; the next change tries again.
    }
  }

  Future<void> _onStarted(QuizStarted _, Emitter<QuizState> emit) async {
    if (state.busy) return;
    final deck = List.generate(quizQuestions.length, (i) => i)..shuffle(_random);
    emit(_copy(busy: true));
    try {
      await gameRepository.start(coupleId: _coupleId, userId: _userId, type: GameType.quiz, state: {'deck': deck.take(roundCount).toList()});
      emit(_copy());
    } catch (_) {
      emit(_copy(error: 'Could not start the game. Check your connection.'));
    }
  }

  Future<void> _onGuessed(QuizGuessed e, Emitter<QuizState> emit) async {
    final s = state.session;
    final round = state.currentRound;
    final self = state.pendingSelf;
    if (s == null || !s.isActive || round == null || self == null || state.busy) return;
    final last = state.myCount == state.rounds - 1;
    emit(_copy(pendingSelf: self, busy: true));
    try {
      await gameRepository.submitAnswer(
        session: s, userId: _userId, round: round, content: {'self': self, 'guess': e.option}, notify: last,
      );
      final ticket = ++_latest;
      emit(_copy());
      await _refresh(s, ticket, emit);
    } on EncryptionNotReady catch (err) {
      emit(_copy(pendingSelf: self, error: err.message));
    } catch (_) {
      emit(_copy(pendingSelf: self, error: 'Could not send your answer. Check your connection.'));
    }
  }

  Future<void> _onEnded(QuizEnded _, Emitter<QuizState> emit) async {
    final s = state.session;
    if (s == null || !s.isActive) return;
    try {
      await gameRepository.finish(s.id);
    } catch (_) {
      emit(_copy(error: 'Could not end the game. Check your connection.'));
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
