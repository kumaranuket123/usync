import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/game_session.dart';
import 'package:usync/domain/games/pen_fight.dart';
import 'package:usync/domain/repositories/i_auth_repository.dart';
import 'package:usync/domain/repositories/i_couple_repository.dart';
import 'package:usync/domain/repositories/i_game_repository.dart';
import 'package:usync/domain/repositories/i_pen_fight_repository.dart';
import 'package:usync/presentation/features/games/bloc/pen_fight_bloc.dart';

class _FakeGames implements IGameRepository {
  final changes = StreamController<List<GameSession>>.broadcast();
  GameType? started;
  Map<String, dynamic>? startedState;

  @override
  Stream<List<GameSession>> watchSessions(String coupleId) => changes.stream;
  @override
  Future<String> start({required String coupleId, required String userId, required GameType type, required Map<String, dynamic> state}) async {
    started = type;
    startedState = state;
    return 'g1';
  }
  @override
  Future<void> finish(String sessionId) async {}
  bool entered = false, left = false;
  @override
  Future<void> enterGame({required String coupleId, required String userId, required GameType type}) async => entered = true;
  @override
  Future<void> leaveGame({required String coupleId, required String userId}) async => left = true;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _FakePens implements IPenFightRepository {
  final incoming = StreamController<PenMessage>.broadcast();
  final presence = StreamController<bool>.broadcast();
  final sent = <PenMessage>[];

  @override
  Stream<bool> watchPartnerHere({required String coupleId, required String userId}) => presence.stream;

  @override
  Future<void> send({required String coupleId, required PenMessage message}) async => sent.add(message);
  @override
  Stream<PenMessage> watch(String coupleId) => incoming.stream;

  Iterable<PenMessage> of(PenMessageType t) => sent.where((m) => m.type == t);
}

class _FakeAuth implements IAuthRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _FakeCouple implements ICoupleRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

GameSession _session({bool active = true, String id = 'g1', String createdBy = 'me', String? difficulty}) => GameSession(
      id: id, coupleId: 'c', type: GameType.penFight, isActive: active, state: {if (difficulty != null) 'difficulty': difficulty}, version: 0,
      updatedAt: DateTime(2026), createdBy: createdBy,
    );

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late _FakeGames games;
  late _FakePens pens;
  late PenFightBloc bloc;

  setUp(() async {
    games = _FakeGames();
    pens  = _FakePens();
    bloc  = PenFightBloc(gameRepository: games, penRepository: pens, authRepository: _FakeAuth(), coupleRepository: _FakeCouple());
    bloc.add(PenFightOpened(coupleId: 'c', userId: 'me'));
    await pump();
  });
  tearDown(() => bloc.close());

  /// Opens a running game whose creator is [createdBy] and has the partner say hello.
  Future<void> openGame({String createdBy = 'me'}) async {
    games.changes.add([_session(createdBy: createdBy)]);
    pens.incoming.add(const PenMessage(type: PenMessageType.hello, from: 'partner'));
    await pump();
  }

  /// Plays the clock forward until the flick has stopped.
  Future<void> settle({bool untilStopped = false}) async {
    await pump(); // let a flick just added be taken in
    bool going() => bloc.state.moving && !(untilStopped && bloc.state.world.settled);
    for (var i = 0; i < 1500 && going(); i++) {
      bloc.add(PenTicked(const Duration(milliseconds: 17)));
      if (i % 20 == 0) await pump();
    }
    await pump();
  }

  test('starts a pen fight game', () async {
    bloc.add(PenFightStarted());
    await pump();
    expect(games.started, GameType.penFight);
  });

  test('says hello when opened and answers the partner\'s hello', () async {
    expect(pens.of(PenMessageType.hello), hasLength(1));
    await openGame();
    expect(bloc.state.partnerHere, isTrue);
    expect(pens.of(PenMessageType.here), hasLength(1));
  });

  test('the player who started the game goes first', () async {
    await openGame();
    expect(bloc.state.turnUserId, 'me');
    await bloc.close();
  });

  test('cannot flick while the partner has not opened the game', () async {
    games.changes.add([_session()]);
    await pump();
    bloc.add(PenFlicked(0, -1, 0.8));
    await pump();
    expect(pens.of(PenMessageType.flick), isEmpty);
    expect(bloc.state.moving, isFalse);
  });

  test('cannot flick on the partner\'s turn', () async {
    await openGame(createdBy: 'partner');
    bloc.add(PenFlicked(0, -1, 0.8));
    await pump();
    expect(pens.of(PenMessageType.flick), isEmpty);
  });

  test('a flick is sent and played, and then the turn passes', () async {
    await openGame();
    bloc.add(PenFlicked(0, -1, 0.3));
    await pump();
    expect(pens.of(PenMessageType.flick), hasLength(1));
    expect(bloc.state.moving, isTrue);

    await settle();
    expect(bloc.state.moving, isFalse);
    expect(pens.of(PenMessageType.settled), hasLength(1));
    expect(bloc.state.turnUserId, 'partner');
    expect(bloc.state.roundOutcome, PenOutcome.none);
  });

  test('a flick too gentle to move the pen is ignored', () async {
    await openGame();
    bloc.add(PenFlicked(0, -1, 0.001));
    await pump();
    expect(pens.of(PenMessageType.flick), isEmpty);
  });

  test('a straight hard flick at the partner\'s pen scores at most one round', () async {
    await openGame();
    bloc.add(PenFlicked(0, -1, 1));
    await settle();
    expect(bloc.state.moving, isFalse);
    expect(bloc.state.myScore + bloc.state.partnerScore, lessThanOrEqualTo(1));
  });

  test('flicking my pen off the desk gives the partner the round, and I start the next', () async {
    await openGame();
    bloc.add(PenFlicked(1, 0, 1));
    await settle();
    expect(bloc.state.roundOutcome, PenOutcome.otherWon);
    expect(bloc.state.partnerScore, 1);
    expect(bloc.state.turnUserId, 'me');
    expect(bloc.state.roundOver, isTrue);

    bloc.add(PenNextRound());
    await pump();
    expect(bloc.state.round, 2);
    expect(bloc.state.roundOutcome, PenOutcome.none);
    expect(bloc.state.world, PenWorld.start());
    expect(pens.of(PenMessageType.next).single.round, 2);
  });

  test('rounds go on with no limit: the score just keeps counting', () async {
    await openGame();
    for (var i = 0; i < 4; i++) {
      bloc.add(PenFlicked(1, 0, 1));
      await settle();
      expect(bloc.state.roundOver, isTrue);
      bloc.add(PenNextRound());
      await pump();
    }
    expect(bloc.state.partnerScore, 4);
    expect(bloc.state.round, 5);
    // Still flickable in round 5.
    bloc.add(PenFlicked(0, -1, 0.3));
    await pump();
    expect(pens.of(PenMessageType.flick), hasLength(5));
  });

  test('the level chosen at the start goes into the session and sets the physics', () async {
    bloc.add(PenFightStarted(PenDifficulty.hard));
    await pump();
    expect(games.startedState, {'difficulty': 'hard'});

    games.changes.add([_session(difficulty: 'hard')]);
    pens.presence.add(true);
    await pump();
    expect(bloc.state.difficulty, PenDifficulty.hard);
    expect(bloc.state.world.difficulty, PenDifficulty.hard);
    bloc.add(PenFlicked(0, -1, 1));
    await pump();
    expect(bloc.state.world.own.speed, closeTo(PenDifficulty.hard.maxSpeed, 1e-9));
  });

  test('the partner\'s flick is shown from my side and the turn comes to me when it settles', () async {
    await openGame(createdBy: 'partner');
    // The partner (bottom of their screen) flicks straight up: on my screen they are at the top, moving down.
    final theirs = PenWorld.start().flicked(0, -1, 0.3);
    pens.incoming.add(PenMessage(type: PenMessageType.flick, from: 'partner', seq: 1, world: theirs));
    await pump();
    expect(bloc.state.moving, isTrue);
    expect(bloc.state.world.other.y, lessThan(bloc.state.world.own.y));
    expect(bloc.state.world.other.vy, greaterThan(0));

    // Their final positions arrive; once my copy of the motion has stopped they are applied.
    final end = PenWorld.start().copyWith(own: const PenBody(x: 0.5, y: 0.9));
    pens.incoming.add(PenMessage(type: PenMessageType.settled, from: 'partner', seq: 1, world: end));
    await settle();
    expect(bloc.state.moving, isFalse);
    expect(bloc.state.world.other.y, closeTo(PenFight.deskHeight - 0.9, 1e-9));
    expect(bloc.state.turnUserId, 'me');
  });

  test('a flick that arrives twice is played once', () async {
    await openGame(createdBy: 'partner');
    final m = PenMessage(type: PenMessageType.flick, from: 'partner', seq: 1, world: PenWorld.start().flicked(0, -1, 0.3));
    pens.incoming..add(m)..add(m);
    await pump();
    final before = bloc.state.world;
    pens.incoming.add(m);
    await pump();
    expect(bloc.state.world, before);
  });

  test('without the partner\'s final positions the phone trusts its own result after a wait', () async {
    await openGame(createdBy: 'partner');
    pens.incoming.add(PenMessage(type: PenMessageType.flick, from: 'partner', seq: 1, world: PenWorld.start().flicked(0, -1, 0.3)));
    await pump();
    await settle(untilStopped: true);
    expect(bloc.state.moving, isTrue, reason: 'still waiting for the partner\'s result');
    for (var i = 0; i < 200; i++) {
      bloc.add(PenTicked(const Duration(milliseconds: 17)));
    }
    await pump();
    expect(bloc.state.moving, isFalse);
    expect(bloc.state.turnUserId, 'me');
  });

  test('a round the partner won is shown, and their "next" starts the next round', () async {
    await openGame(createdBy: 'partner');
    // The partner flicks off the side of the desk.
    final theirs = PenWorld.start().flicked(1, 0, 1);
    pens.incoming.add(PenMessage(type: PenMessageType.flick, from: 'partner', seq: 1, world: theirs));
    await pump();
    final fallen = _runToEnd(theirs);
    pens.incoming.add(PenMessage(type: PenMessageType.settled, from: 'partner', seq: 1, world: fallen));
    await settle();
    expect(bloc.state.roundOutcome, PenOutcome.ownWon);
    expect(bloc.state.myScore, 1);

    pens.incoming.add(const PenMessage(type: PenMessageType.next, from: 'partner', round: 2));
    await pump();
    expect(bloc.state.round, 2);
    expect(bloc.state.roundOutcome, PenOutcome.none);
  });

  test('the partner is here as soon as Presence says so, with no hello at all', () async {
    games.changes.add([_session()]);
    pens.presence.add(true);
    await pump();
    expect(bloc.state.partnerHere, isTrue);
    expect(games.entered, isTrue, reason: 'this phone announces the screen on Presence');
    bloc.add(PenFlicked(0, -1, 0.3));
    await pump();
    expect(pens.of(PenMessageType.flick), hasLength(1));

    pens.presence.add(false);
    await pump();
    expect(bloc.state.partnerHere, isFalse);
  });

  test('closing the screen takes the announcement back', () async {
    await bloc.close();
    expect(games.left, isTrue);
  });

  test('the partner leaving stops flicks', () async {
    await openGame();
    pens.incoming.add(const PenMessage(type: PenMessageType.bye, from: 'partner'));
    await pump();
    expect(bloc.state.partnerHere, isFalse);
    bloc.add(PenFlicked(0, -1, 0.8));
    await pump();
    expect(pens.of(PenMessageType.flick), isEmpty);
  });

  test('a new game resets scores and pens', () async {
    await openGame();
    bloc.add(PenFlicked(1, 0, 1));
    await settle();
    expect(bloc.state.partnerScore, 1);
    games.changes.add([_session(id: 'g2')]);
    await pump();
    expect(bloc.state.partnerScore, 0);
    expect(bloc.state.round, 1);
    expect(bloc.state.world, PenWorld.start());
  });
}

PenWorld _runToEnd(PenWorld w) {
  for (var i = 0; i < 2000 && !w.settled; i++) {
    w = w.step();
  }
  return w;
}
