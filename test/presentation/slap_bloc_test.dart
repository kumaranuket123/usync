import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/couple.dart';
import 'package:usync/domain/entities/game_session.dart';
import 'package:usync/domain/entities/user.dart';
import 'package:usync/domain/repositories/i_auth_repository.dart';
import 'package:usync/domain/repositories/i_couple_repository.dart';
import 'package:usync/domain/repositories/i_game_repository.dart';
import 'package:usync/domain/repositories/i_slap_repository.dart';
import 'package:usync/presentation/features/games/bloc/slap_bloc.dart';

class _FakeGames implements IGameRepository {
  final changes = StreamController<List<GameSession>>.broadcast();
  GameType? started;

  @override
  Stream<List<GameSession>> watchSessions(String coupleId) => changes.stream;
  @override
  Future<String> start({required String coupleId, required String userId, required GameType type, required Map<String, dynamic> state}) async {
    started = type;
    return 'g1';
  }
  @override
  Future<void> finish(String sessionId) async {}
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _FakeSlaps implements ISlapRepository {
  final incoming = StreamController<String>.broadcast();
  final sent = <String>[];

  @override
  Future<void> slap({required String coupleId, required String userId}) async => sent.add(userId);
  @override
  Stream<String> watchSlaps(String coupleId) => incoming.stream;
}

AppUser _user(String id, String emoji, String name) =>
    AppUser(id: id, username: name, email: '', avatarEmoji: emoji, createdAt: DateTime(2026));

class _LoadedAuth implements IAuthRepository {
  @override
  Future<AppUser?> getCurrentUser() async => _user('me', '🦊', 'Me');
  @override
  Future<AppUser?> getUserById(String uid) async => _user(uid, '🐼', 'Panda');
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _LoadedCouple implements ICoupleRepository {
  @override
  Future<Couple> getCouple(String coupleId) async =>
      Couple(id: 'c', userAId: 'me', userBId: 'partner', pairedAt: DateTime(2026));
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _FakeAuth implements IAuthRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _FakeCouple implements ICoupleRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

GameSession _session({bool active = true, String id = 'g1'}) => GameSession(
      id: id, coupleId: 'c', type: GameType.slap, isActive: active, state: const {}, version: 0,
      updatedAt: DateTime(2026),
    );

void main() {
  late _FakeGames games;
  late _FakeSlaps slaps;
  late SlapBloc bloc;

  setUp(() async {
    games = _FakeGames();
    slaps = _FakeSlaps();
    bloc  = SlapBloc(gameRepository: games, slapRepository: slaps, authRepository: _FakeAuth(), coupleRepository: _FakeCouple(), minGap: Duration.zero);
    bloc.add(SlapOpened(coupleId: 'c', userId: 'me'));
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() => bloc.close());

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 10));

  test('starts a slap game', () async {
    bloc.add(SlapStarted());
    await pump();
    expect(games.started, GameType.slap);
  });

  test('counts and sends my slaps while the game runs', () async {
    games.changes.add([_session()]);
    await pump();
    bloc.add(SlapSent());
    bloc.add(SlapSent());
    await pump();
    expect(slaps.sent, ['me', 'me']);
    expect(bloc.state.given, 2);
  });

  test('does not slap without a running game', () async {
    games.changes.add([_session(active: false)]);
    await pump();
    bloc.add(SlapSent());
    await pump();
    expect(slaps.sent, isEmpty);
    expect(bloc.state.given, 0);
  });

  test('counts the partner\'s slaps but not my own echo', () async {
    games.changes.add([_session()]);
    await pump();
    slaps.incoming..add('partner')..add('me');
    await pump();
    expect(bloc.state.received, 1);
  });

  test('rate limits slaps sent too close together', () async {
    final limited = SlapBloc(gameRepository: games, slapRepository: slaps, authRepository: _FakeAuth(), coupleRepository: _FakeCouple(), minGap: const Duration(seconds: 5));
    limited.add(SlapOpened(coupleId: 'c', userId: 'me'));
    await pump();
    games.changes.add([_session()]);
    await pump();
    limited.add(SlapSent());
    limited.add(SlapSent());
    await pump();
    expect(limited.state.given, 1);
    await limited.close();
  });

  test('loads both avatars for the screen', () async {
    final b = SlapBloc(gameRepository: games, slapRepository: slaps, authRepository: _LoadedAuth(), coupleRepository: _LoadedCouple());
    b.add(SlapOpened(coupleId: 'c', userId: 'me'));
    await pump();
    expect(b.state.players.ownEmoji, '🦊');
    expect(b.state.players.partnerEmoji, '🐼');
    expect(b.state.players.partnerName, 'Panda');
    await b.close();
  });

  test('keeps the default avatars when they cannot be loaded', () async {
    expect(bloc.state.players, const SlapPlayers());
  });

  test('a new game resets the count', () async {
    games.changes.add([_session()]);
    await pump();
    bloc.add(SlapSent());
    await pump();
    games.changes.add([_session(id: 'g2')]);
    await pump();
    expect(bloc.state.given, 0);
  });
}
