import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/constants/game_content.dart';
import 'package:usync/domain/entities/game_answer.dart';
import 'package:usync/domain/entities/game_session.dart';
import 'package:usync/domain/repositories/i_game_repository.dart';
import 'package:usync/presentation/features/games/bloc/cards_bloc.dart';

class _FakeGameRepository implements IGameRepository {
  final changes  = StreamController<List<GameSession>>.broadcast();
  final updates  = <Map<String, dynamic>>[];
  final finished = <String>[];
  Map<String, dynamic>? startedState;
  Object? error;

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
  Future<void> updateState({required GameSession session, required Map<String, dynamic> state}) async {
    if (error != null) throw error!;
    updates.add(state);
  }

  @override
  Future<void> enterGame({required String coupleId, required String userId, required GameType type}) async {}

  @override
  Future<void> leaveGame({required String coupleId, required String userId}) async {}

  @override
  Future<void> finish(String sessionId) async => finished.add(sessionId);

  @override
  Future<void> submitAnswer({required GameSession session, required String userId, required int round, required Map<String, dynamic> content, bool notify = false}) async {}

  @override
  Future<List<GameAnswer>> getAnswers(GameSession session) async => const [];
}

GameSession _session({int pos = 0, bool active = true}) => GameSession(
      id: 'g1', coupleId: 'c1', type: GameType.cards, isActive: active, version: 1,
      updatedAt: DateTime(2026), state: {'deck': const [4, 11, 22], 'pos': pos},
    );

void main() {
  late _FakeGameRepository games;
  late CardsBloc bloc;

  setUp(() async {
    games = _FakeGameRepository();
    bloc  = CardsBloc(gameRepository: games, cardCount: 3, random: Random(1));
    bloc.add(CardsOpened(coupleId: 'c1', userId: 'me'));
    await pumpEventQueue();
  });
  tearDown(() => bloc.close());

  test('starting deals distinct cards at position 0', () async {
    games.changes.add([]);
    await pumpEventQueue();
    bloc.add(CardsStarted());
    await pumpEventQueue();

    final deck = (games.startedState!['deck'] as List).cast<int>();
    expect(deck.toSet(), hasLength(3));
    expect(deck.every((i) => i >= 0 && i < conversationCards.length), isTrue);
    expect(games.startedState!['pos'], 0);
  });

  test('shows the card at the shared position', () async {
    games.changes.add([_session(pos: 1)]);
    await pumpEventQueue();

    expect(bloc.state.card, same(conversationCards[11]));
    expect(bloc.state.isLast, isFalse);
  });

  test('next moves the shared position on and keeps the deck', () async {
    games.changes.add([_session()]);
    await pumpEventQueue();

    bloc.add(CardsNext());
    await pumpEventQueue();

    expect(games.updates.single, {'deck': [4, 11, 22], 'pos': 1});
    expect(games.finished, isEmpty);
  });

  test('next on the last card ends the game', () async {
    games.changes.add([_session(pos: 2)]);
    await pumpEventQueue();
    expect(bloc.state.isLast, isTrue);

    bloc.add(CardsNext());
    await pumpEventQueue();

    expect(games.finished, ['g1']);
    expect(games.updates, isEmpty);
  });

  test('a rejected turn reports an error', () async {
    games.changes.add([_session()]);
    await pumpEventQueue();
    games.error = Exception('out of date');

    bloc.add(CardsNext());
    await pumpEventQueue();

    expect(bloc.state.error, isNotNull);
    expect(bloc.state.busy, isFalse);
  });

  test('a finished game shows no card', () async {
    games.changes.add([_session(active: false)]);
    await pumpEventQueue();

    bloc.add(CardsNext());
    await pumpEventQueue();

    expect(games.updates, isEmpty);
    expect(games.finished, isEmpty);
  });

  test('every card has text', () {
    for (final c in conversationCards) {
      expect(c.text.trim(), isNotEmpty);
    }
    expect(conversationCards.length, greaterThanOrEqualTo(15));
  });
}
