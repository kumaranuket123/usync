import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/couple.dart';
import 'package:usync/domain/entities/game_answer.dart';
import 'package:usync/domain/entities/game_session.dart';
import 'package:usync/domain/repositories/i_couple_repository.dart';
import 'package:usync/domain/repositories/i_game_repository.dart';
import 'package:usync/presentation/features/games/bloc/tic_tac_toe_bloc.dart';

class _FakeGameRepository implements IGameRepository {
  final changes = StreamController<List<GameSession>>.broadcast();
  final moves   = <({Map<String, dynamic> state, bool finish})>[];
  int started   = 0;
  final presence = <String>[]; // 'enter' / 'leave', in order
  Object? error;

  @override
  Stream<List<GameSession>> watchSessions(String coupleId) => changes.stream;

  @override
  Future<String> start({required String coupleId, required String userId, required GameType type, required Map<String, dynamic> state}) async {
    if (error != null) throw error!;
    started++;
    return 'g1';
  }

  @override
  Future<void> makeMove({required GameSession session, required String userId, required Map<String, dynamic> state, bool finish = false}) async {
    if (error != null) throw error!;
    moves.add((state: state, finish: finish));
  }

  @override
  Future<void> updateState({required GameSession session, required Map<String, dynamic> state}) async {}

  @override
  Future<void> enterGame({required String coupleId, required String userId, required GameType type}) async => presence.add('enter');

  @override
  Future<void> leaveGame({required String coupleId, required String userId}) async => presence.add('leave');

  @override
  Future<void> finish(String sessionId) async {}

  @override
  Future<void> submitAnswer({required GameSession session, required String userId, required int round, required Map<String, dynamic> content, bool notify = false}) async {}

  @override
  Future<List<GameAnswer>> getAnswers(GameSession session) async => const [];
}

class _FakeCoupleRepository implements ICoupleRepository {
  @override
  Future<Couple> getCouple(String coupleId) async =>
      Couple(id: coupleId, userAId: 'me', userBId: 'partner', pairedAt: DateTime(2026));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GameSession _session({String board = '         ', String? turn = 'me', bool active = true, int version = 0}) => GameSession(
      id: 'g1', coupleId: 'c1', type: GameType.ticTacToe, isActive: active, version: version,
      updatedAt: DateTime(2026), turnUserId: turn,
      state: {'board': board, 'x': 'me', 'o': 'partner'},
    );

void main() {
  late _FakeGameRepository games;
  late TicTacToeBloc bloc;

  setUp(() async {
    games = _FakeGameRepository();
    bloc  = TicTacToeBloc(gameRepository: games, coupleRepository: _FakeCoupleRepository());
    bloc.add(TicTacToeOpened(coupleId: 'c1', userId: 'me'));
    await pumpEventQueue();
  });
  tearDown(() => bloc.close());

  test('shows no game until one exists, then starts one', () async {
    games.changes.add([]);
    await pumpEventQueue();
    expect(bloc.state.loading, isFalse);
    expect(bloc.state.session, isNull);

    bloc.add(TicTacToeStarted());
    await pumpEventQueue();
    expect(games.started, 1);
  });

  test('plays a move on my turn and keeps the game going', () async {
    games.changes.add([_session()]);
    await pumpEventQueue();

    bloc.add(TicTacToeCellTapped(4));
    await pumpEventQueue();

    expect(games.moves, hasLength(1));
    expect(games.moves.single.state['board'], '    X    ');
    expect(games.moves.single.finish, isFalse);
  });

  test('ignores a tap when it is not my turn', () async {
    games.changes.add([_session(turn: 'partner')]);
    await pumpEventQueue();

    bloc.add(TicTacToeCellTapped(4));
    await pumpEventQueue();

    expect(games.moves, isEmpty);
  });

  test('the winning move finishes the game with its result', () async {
    games.changes.add([_session(board: 'XX OO    ')]);
    await pumpEventQueue();

    bloc.add(TicTacToeCellTapped(2));
    await pumpEventQueue();

    expect(games.moves.single.finish, isTrue);
    expect(games.moves.single.state['result'], 'X');
  });

  test('a failed move reports an error and keeps the board', () async {
    games.changes.add([_session()]);
    await pumpEventQueue();
    games.error = Exception('out of date');

    bloc.add(TicTacToeCellTapped(0));
    await pumpEventQueue();

    expect(bloc.state.error, isNotNull);
    expect(bloc.state.busy, isFalse);
  });

  test('the running game is shown over a finished one', () async {
    games.changes.add([
      _session(active: false, turn: null),
      _session(),
    ]);
    await pumpEventQueue();
    expect(bloc.state.session!.isActive, isTrue);
  });

  test('announces itself on open, and again when the app comes back', () async {
    expect(games.presence, ['enter']);

    bloc.add(TicTacToeHidden());
    bloc.add(TicTacToeShown());
    await pumpEventQueue();

    expect(games.presence, ['enter', 'leave', 'enter']);
  });

  test('takes the announcement back when the screen closes', () async {
    await bloc.close();
    expect(games.presence.last, 'leave');
  });
}
