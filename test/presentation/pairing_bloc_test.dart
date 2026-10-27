import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/couple.dart';
import 'package:usync/domain/repositories/i_couple_repository.dart';
import 'package:usync/presentation/features/pairing/bloc/pairing_bloc.dart';

class _FakeCoupleRepository implements ICoupleRepository {
  Object? error;
  final joined = StreamController<void>.broadcast();
  final couple = Couple(id: 'c1', userAId: 'a', userBId: 'b', pairedAt: DateTime(2026));

  @override
  Future<String> generateInviteCode(String userId) async {
    if (error != null) throw error!;
    return 'AB12';
  }

  @override
  Future<Couple> joinWithCode(String code, String userId) async {
    if (error != null) throw error!;
    return couple;
  }

  @override
  Stream<void> watchPartnerJoined(String userId) => joined.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _FakeCoupleRepository repo;
  late PairingBloc bloc;
  late List<PairingState> states;
  late StreamSubscription<PairingState> sub;

  setUp(() {
    repo = _FakeCoupleRepository();
    bloc = PairingBloc(coupleRepository: repo);
    states = [];
    sub = bloc.stream.listen(states.add);
  });

  tearDown(() async {
    await sub.cancel();
    await bloc.close();
    await repo.joined.close();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('starts in the initial state', () {
    expect(bloc.state, isA<PairingInitial>());
  });

  test('generating a code emits loading then the code', () async {
    bloc.add(GenerateCodeRequested('u1'));
    await settle();
    expect(states.map((s) => s.runtimeType), [PairingLoading, CodeGenerated]);
    expect((states.last as CodeGenerated).code, 'AB12');
  });

  test('a failed code generation emits an error', () async {
    repo.error = Exception('boom');
    bloc.add(GenerateCodeRequested('u1'));
    await settle();
    expect(states.last, isA<PairingError>());
  });

  test('joining with a valid code emits success with the couple', () async {
    bloc.add(JoinWithCodeRequested(code: 'AB12', userId: 'u2'));
    await settle();
    expect(states.map((s) => s.runtimeType), [PairingLoading, PairingSuccess]);
    expect((states.last as PairingSuccess).couple, repo.couple);
  });

  test('joining with a rejected code emits the server message', () async {
    repo.error = Exception('Invalid invite code');
    bloc.add(JoinWithCodeRequested(code: 'ZZZZ', userId: 'u2'));
    await settle();
    expect((states.last as PairingError).message, contains('Invalid invite code'));
  });

  test('the inviter is told when the partner joins', () async {
    bloc.add(WatchPartnerJoined('u1'));
    await settle();
    repo.joined.add(null);
    await settle();
    expect(states.last, isA<PartnerJoined>());
  });

  test('reset returns to the initial state', () async {
    repo.error = Exception('x');
    bloc.add(GenerateCodeRequested('u1'));
    await settle();
    bloc.add(PairingReset());
    await settle();
    expect(states.last, isA<PairingInitial>());
  });
}
