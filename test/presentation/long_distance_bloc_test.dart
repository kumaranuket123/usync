import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/couple.dart';
import 'package:usync/domain/entities/shared_location.dart';
import 'package:usync/domain/repositories/i_couple_repository.dart';
import 'package:usync/domain/repositories/i_location_repository.dart';
import 'package:usync/presentation/features/long_distance/bloc/long_distance_bloc.dart';

class _FakeCouples implements ICoupleRepository {
  _FakeCouples(this.couple);
  Couple couple;
  bool getFails = false;
  bool saveFails = false;
  final changes = StreamController<Couple>.broadcast();
  final saved = <DateTime?>[];

  @override
  Future<Couple> getCouple(String coupleId) async {
    if (getFails) throw Exception('offline');
    return couple;
  }

  @override
  Stream<Couple> watchCouple(String coupleId) => changes.stream;

  @override
  Future<void> setNextMeet(String coupleId, String userId, DateTime? day) async {
    if (saveFails) throw Exception('offline');
    saved.add(day);
    couple = _couple(mode: couple.relationshipMode, meet: day);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocations implements ILocationRepository {
  SharedLocation? own, partner;
  final partnerChanges = StreamController<SharedLocation?>.broadcast();

  @override
  Future<SharedLocation?> getPartnerLocation(String userId) async => userId == 'me' ? own : partner;

  @override
  Stream<SharedLocation?> watchPartnerLocation(String partnerUserId) => partnerChanges.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Couple _couple({RelationshipMode mode = RelationshipMode.longDistance, DateTime? meet}) => Couple(
      id: 'c',
      userAId: 'me',
      userBId: 'you',
      pairedAt: DateTime(2026),
      relationshipMode: mode,
      nextMeetOn: meet,
    );

SharedLocation _loc(double lat, double lon) =>
    SharedLocation(latitude: lat, longitude: lon, accuracy: 5, timestamp: DateTime(2026));

void main() {
  late _FakeCouples couples;
  late _FakeLocations locations;
  late LongDistanceBloc bloc;

  setUp(() {
    couples = _FakeCouples(_couple());
    locations = _FakeLocations();
    bloc = LongDistanceBloc(coupleRepository: couples, locationRepository: locations);
  });

  tearDown(() => bloc.close());

  Future<void> start() async {
    bloc.add(LongDistanceStarted(coupleId: 'c', userId: 'me', partnerId: 'you'));
    await bloc.stream.firstWhere((s) => s.visible || !s.visible);
    await pumpEventQueue();
  }

  test('is hidden for couples who live together', () async {
    couples.couple = _couple(mode: RelationshipMode.together);
    await start();
    expect(bloc.state.visible, isFalse);
  });

  test('is shown for long-distance couples, with no distance until both share', () async {
    await start();
    expect(bloc.state.visible, isTrue);
    expect(bloc.state.distanceMetres, isNull);
  });

  test('computes the distance once both locations are known', () async {
    locations.own = _loc(28.6139, 77.2090);
    await start();
    locations.partnerChanges.add(_loc(19.0760, 72.8777));
    await pumpEventQueue();
    expect(bloc.state.distanceMetres! / 1000, inInclusiveRange(1140, 1160));
  });

  test('follows the partner switching the mode', () async {
    await start();
    couples.changes.add(_couple(mode: RelationshipMode.together));
    await pumpEventQueue();
    expect(bloc.state.visible, isFalse);
  });

  test('counts days to the next meet; a past date counts as none', () async {
    final today = DateTime(2026, 6, 10);
    expect(const LongDistanceState().daysUntilMeet(today), isNull);
    expect(LongDistanceState(nextMeetOn: DateTime(2026, 6, 10)).daysUntilMeet(today), 0);
    expect(LongDistanceState(nextMeetOn: DateTime(2026, 6, 22)).daysUntilMeet(today), 12);
    expect(LongDistanceState(nextMeetOn: DateTime(2026, 6, 9)).daysUntilMeet(today), isNull);
  });

  test('choosing a date saves it and shows it', () async {
    await start();
    bloc.add(NextMeetChosen(DateTime(2026, 12, 12)));
    await pumpEventQueue();
    expect(couples.saved, [DateTime(2026, 12, 12)]);
    expect(bloc.state.nextMeetOn, DateTime(2026, 12, 12));
  });

  test('a failed save keeps the old date and reports an error', () async {
    couples.couple = _couple(meet: DateTime(2026, 7, 1));
    await start();
    couples.saveFails = true;
    bloc.add(NextMeetChosen(DateTime(2026, 12, 12)));
    await pumpEventQueue();
    expect(bloc.state.nextMeetOn, DateTime(2026, 7, 1));
    expect(bloc.state.error, contains('Could not save'));
  });

  test('stays hidden when the couple cannot be read', () async {
    couples.getFails = true;
    bloc.add(LongDistanceStarted(coupleId: 'c', userId: 'me', partnerId: 'you'));
    await pumpEventQueue();
    expect(bloc.state.visible, isFalse);
  });
}
