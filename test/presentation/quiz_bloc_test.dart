import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/constants/game_content.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/domain/entities/game_answer.dart';
import 'package:usync/domain/entities/game_session.dart';
import 'package:usync/domain/repositories/i_game_repository.dart';
import 'package:usync/presentation/features/games/bloc/quiz_bloc.dart';

class _FakeGameRepository implements IGameRepository {
  final changes  = StreamController<List<GameSession>>.broadcast();
  final sent     = <({int round, Map<String, dynamic> content, bool notify})>[];
  final finished = <String>[];
  Map<String, dynamic>? startedState;
  List<GameAnswer> answers = [];
  Object? submitError;

  @override
  Stream<List<GameSession>> watchSessions(String coupleId) => changes.stream;

  @override
  Future<String> start({required String coupleId, required String userId, required GameType type, required Map<String, dynamic> state}) async {
    startedState = state;
    return 'g1';
  }

  @override
  Future<void> makeMove({required GameSession session, required String userId, required Map<String, dynamic> state, bool finish = false}) async {}

  @override
  Future<void> updateState({required GameSession session, required Map<String, dynamic> state}) async {}

  @override
  Future<void> enterGame({required String coupleId, required String userId, required GameType type}) async {}

  @override
  Future<void> leaveGame({required String coupleId, required String userId}) async {}

  @override
  Future<void> finish(String sessionId) async => finished.add(sessionId);

  @override
  Future<void> submitAnswer({required GameSession session, required String userId, required int round, required Map<String, dynamic> content, bool notify = false}) async {
    if (submitError != null) throw submitError!;
    sent.add((round: round, content: content, notify: notify));
    answers = [...answers, GameAnswer(round: round, userId: userId, content: content)];
  }

  @override
  Future<List<GameAnswer>> getAnswers(GameSession session) async => answers;
}

GameAnswer _a(String user, int round, int self, int guess) =>
    GameAnswer(round: round, userId: user, content: {'self': self, 'guess': guess});

GameSession _session({bool active = true}) => GameSession(
      id: 'g1', coupleId: 'c1', type: GameType.quiz, isActive: active, version: 1,
      updatedAt: DateTime(2026), state: const {'deck': [0, 1, 2]},
    );

void main() {
  late _FakeGameRepository games;
  late QuizBloc bloc;

  setUp(() async {
    games = _FakeGameRepository();
    bloc  = QuizBloc(gameRepository: games, roundCount: 3, random: Random(1));
    bloc.add(QuizOpened(coupleId: 'c1', userId: 'me'));
    await pumpEventQueue();
  });
  tearDown(() => bloc.close());

  test('starting a game deals distinct topics', () async {
    games.changes.add([]);
    await pumpEventQueue();
    bloc.add(QuizStarted());
    await pumpEventQueue();

    final deck = (games.startedState!['deck'] as List).cast<int>();
    expect(deck.toSet(), hasLength(3));
    expect(deck.every((i) => i >= 0 && i < quizQuestions.length), isTrue);
  });

  test('a round sends the own answer and the guess together, only after the guess', () async {
    games.changes.add([_session()]);
    await pumpEventQueue();

    bloc.add(QuizSelfPicked(2));
    await pumpEventQueue();
    expect(games.sent, isEmpty);
    expect(bloc.state.pendingSelf, 2);

    bloc.add(QuizGuessed(1));
    await pumpEventQueue();

    expect(games.sent.single.round, 0);
    expect(games.sent.single.content, {'self': 2, 'guess': 1});
    expect(bloc.state.pendingSelf, isNull);
    expect(bloc.state.currentRound, 1);
  });

  test('a guess without an own answer is ignored; the own answer can be changed', () async {
    games.changes.add([_session()]);
    await pumpEventQueue();

    bloc.add(QuizGuessed(1));
    await pumpEventQueue();
    expect(games.sent, isEmpty);

    bloc.add(QuizSelfPicked(0));
    bloc.add(QuizSelfCleared());
    await pumpEventQueue();
    expect(bloc.state.pendingSelf, isNull);
  });

  test('notifies the partner only on the last round', () async {
    games.changes.add([_session()]);
    await pumpEventQueue();

    for (var r = 0; r < 3; r++) {
      bloc.add(QuizSelfPicked(0));
      bloc.add(QuizGuessed(0));
      await pumpEventQueue();
    }

    expect(games.sent.map((s) => s.notify), [false, false, true]);
    expect(bloc.state.currentRound, isNull);
  });

  test('scores both players once the partner rows are returned', () async {
    games.answers = [
      _a('me', 0, 1, 2), _a('partner', 0, 2, 1), // I guessed their 2, they guessed my 1: both right
      _a('me', 1, 0, 3), _a('partner', 1, 1, 0), // I guessed wrong, they guessed my 0 right
    ];
    games.changes.add([_session()]);
    await pumpEventQueue();

    expect(bloc.state.myScore, 1);
    expect(bloc.state.partnerScore, 2);
    expect(bloc.state.currentRound, 2);
    expect(games.finished, isEmpty);
  });

  test('the game ends once both have answered every round', () async {
    games.answers = [for (var r = 0; r < 3; r++) ...[_a('me', r, 0, 0), _a('partner', r, 0, 0)]];
    games.changes.add([_session()]);
    await pumpEventQueue();

    expect(games.finished, ['g1']);
  });

  test('a missing couple key keeps the own answer and reports it', () async {
    games.changes.add([_session()]);
    await pumpEventQueue();
    games.submitError = const EncryptionNotReady();

    bloc.add(QuizSelfPicked(1));
    bloc.add(QuizGuessed(2));
    await pumpEventQueue();

    expect(bloc.state.error, const EncryptionNotReady().message);
    expect(bloc.state.pendingSelf, 1);
    expect(bloc.state.busy, isFalse);
  });

  test('every topic has four distinct options', () {
    for (final q in quizQuestions) {
      expect(q.options, hasLength(4), reason: q.topic);
      expect(q.options.toSet(), hasLength(4), reason: q.topic);
    }
  });
}
