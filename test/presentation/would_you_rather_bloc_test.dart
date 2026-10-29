import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/constants/game_content.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/domain/entities/game_answer.dart';
import 'package:usync/domain/entities/game_session.dart';
import 'package:usync/domain/repositories/i_couple_repository.dart';
import 'package:usync/domain/repositories/i_game_repository.dart';
import 'package:usync/presentation/features/games/bloc/would_you_rather_bloc.dart';

class _FakeGameRepository implements IGameRepository {
  final changes = StreamController<List<GameSession>>.broadcast();
  final sent      = <({int round, Map<String, dynamic> content, bool notify})>[];
  final finished  = <String>[];
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

class _FakeCoupleRepository implements ICoupleRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GameAnswer _a(String user, int round, String pick) => GameAnswer(round: round, userId: user, content: {'pick': pick});

GameSession _session({bool active = true}) => GameSession(
      id: 'g1', coupleId: 'c1', type: GameType.wouldYouRather, isActive: active, version: 1,
      updatedAt: DateTime(2026), state: const {'deck': [3, 7, 9]},
    );

void main() {
  late _FakeGameRepository games;
  late WouldYouRatherBloc bloc;

  setUp(() async {
    games = _FakeGameRepository();
    bloc  = WouldYouRatherBloc(gameRepository: games, coupleRepository: _FakeCoupleRepository(), roundCount: 3, random: Random(1));
    bloc.add(WouldYouRatherOpened(coupleId: 'c1', userId: 'me'));
    await pumpEventQueue();
  });
  tearDown(() => bloc.close());

  test('starting a game deals a deck of distinct questions', () async {
    games.changes.add([]);
    await pumpEventQueue();
    bloc.add(WouldYouRatherStarted());
    await pumpEventQueue();

    final deck = (games.startedState!['deck'] as List).cast<int>();
    expect(deck, hasLength(3));
    expect(deck.toSet(), hasLength(3));
    expect(deck.every((i) => i >= 0 && i < wouldYouRatherQuestions.length), isTrue);
  });

  test('walks through the rounds in order and notifies only on the last one', () async {
    games.changes.add([_session()]);
    await pumpEventQueue();
    expect(bloc.state.currentRound, 0);

    for (final pick in ['A', 'B', 'A']) {
      bloc.add(WouldYouRatherPicked(pick));
      await pumpEventQueue();
    }

    expect(games.sent.map((s) => s.round), [0, 1, 2]);
    expect(games.sent.map((s) => s.notify), [false, false, true]);
    expect(bloc.state.currentRound, isNull);
  });

  test("the partner's pick is only known when the server returned it, and matches are counted", () async {
    games.answers = [_a('me', 0, 'A'), _a('partner', 0, 'A'), _a('me', 1, 'B'), _a('partner', 1, 'A'), _a('me', 2, 'A')];
    games.changes.add([_session()]);
    await pumpEventQueue();

    expect(bloc.state.partnerPick(0), 'A');
    expect(bloc.state.partnerAnswered(2), isFalse);
    expect(bloc.state.matches, 1);
    expect(games.finished, isEmpty); // the partner has not answered every round yet
  });

  test('the game ends once both have answered every round', () async {
    games.answers = [
      for (var r = 0; r < 3; r++) ...[_a('me', r, 'A'), _a('partner', r, 'B')],
    ];
    games.changes.add([_session()]);
    await pumpEventQueue();

    expect(games.finished, ['g1']);
  });

  test('a missing couple key is reported and nothing is recorded', () async {
    games.changes.add([_session()]);
    await pumpEventQueue();
    games.submitError = const EncryptionNotReady();

    bloc.add(WouldYouRatherPicked('A'));
    await pumpEventQueue();

    expect(bloc.state.error, const EncryptionNotReady().message);
    expect(bloc.state.busy, isFalse);
    expect(bloc.state.currentRound, 0);
  });

  test('ignores a pick once the game is over', () async {
    games.changes.add([_session(active: false)]);
    await pumpEventQueue();

    bloc.add(WouldYouRatherPicked('A'));
    await pumpEventQueue();

    expect(games.sent, isEmpty);
  });

  test('every question has two different options', () {
    for (final q in wouldYouRatherQuestions) {
      expect(q.a.trim(), isNotEmpty);
      expect(q.b.trim(), isNotEmpty);
      expect(q.a, isNot(q.b));
    }
    expect(wouldYouRatherQuestions.length, greaterThanOrEqualTo(10));
  });
}
