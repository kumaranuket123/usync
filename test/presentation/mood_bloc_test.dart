import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/mood.dart';
import 'package:usync/domain/repositories/i_mood_repository.dart';
import 'package:usync/presentation/features/mood/bloc/mood_bloc.dart';

class _FakeMoodRepository implements IMoodRepository {
  Mood? last;
  List<CustomMood> customs = [];
  bool lastFails = false;
  bool customsFail = false;
  bool sentNow = true;
  Object? sendError;
  final sent = <({MoodType type, CustomMood? custom})>[];

  @override
  Future<Mood?> getLastSentMood(String userId) async {
    if (lastFails) throw Exception('offline');
    return last;
  }

  @override
  Future<List<CustomMood>> getMyCustomMoods(String userId, {int limit = 6}) async {
    if (customsFail) throw Exception('no table');
    return customs;
  }

  @override
  Future<bool> sendMood(String coupleId, String userId, MoodType type, {CustomMood? custom}) async {
    if (sendError != null) throw sendError!;
    sent.add((type: type, custom: custom));
    return sentNow;
  }

  @override
  Stream<List<Mood>> watchRecentMoods(String coupleId) => const Stream.empty();
}

void main() {
  late _FakeMoodRepository repo;
  late MoodBloc bloc;
  late List<MoodState> states;
  late StreamSubscription<MoodState> sub;

  setUp(() {
    repo = _FakeMoodRepository();
    bloc = MoodBloc(moodRepository: repo);
    states = [];
    sub = bloc.stream.listen(states.add);
  });

  tearDown(() async {
    await sub.cancel();
    await bloc.close();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> open() async {
    bloc.add(MoodScreenOpened(coupleId: 'c1', userId: 'u1'));
    await settle();
  }

  test('opening preselects the last mood and offers saved custom moods', () async {
    repo.last = Mood(type: MoodType.missingYou, userId: 'u1', sentAt: DateTime(2026));
    repo.customs = [const CustomMood(label: 'Cozy', emoji: '🧸')];
    await open();
    final ready = states.last as MoodReady;
    expect(states.first, isA<MoodLoading>());
    expect(ready.selectedMood, MoodType.missingYou);
    expect(ready.customMoods, repo.customs);
  });

  test('opening restores a custom last mood with its text and emoji', () async {
    repo.last = Mood(
        type: MoodType.custom, userId: 'u1', sentAt: DateTime(2026), customLabel: 'Cozy', customEmoji: '🧸');
    await open();
    expect((states.last as MoodReady).selectedCustom, const CustomMood(label: 'Cozy', emoji: '🧸'));
  });

  test('offline lookups still open the screen with nothing selected', () async {
    repo.lastFails = true;
    repo.customsFail = true;
    await open();
    final ready = states.last as MoodReady;
    expect(ready.selectedMood, isNull);
    expect(ready.customMoods, isEmpty);
  });

  test('selecting a built-in mood clears a previous custom choice', () async {
    await open();
    bloc.add(CustomMoodSelected(const CustomMood(label: 'Cozy', emoji: '🧸')));
    bloc.add(MoodSelected(MoodType.happy));
    await settle();
    final ready = states.last as MoodReady;
    expect(ready.selectedMood, MoodType.happy);
    expect(ready.selectedCustom, isNull);
  });

  test('a new custom mood is selected and moved to the front without repeats', () async {
    const cozy = CustomMood(label: 'Cozy', emoji: '🧸');
    const calm = CustomMood(label: 'Calm', emoji: '🌊');
    repo.customs = [cozy, calm];
    await open();
    bloc.add(CustomMoodAdded(calm));
    await settle();
    final ready = states.last as MoodReady;
    expect(ready.selectedMood, MoodType.custom);
    expect(ready.selectedCustom, calm);
    expect(ready.customMoods, [calm, cozy]);
  });

  test('sending without a selection asks to pick a mood', () async {
    await open();
    bloc.add(MoodSent());
    await settle();
    expect((states.last as MoodError).message, 'Pick a mood first');
    expect(repo.sent, isEmpty);
  });

  test('sending a custom mood without its text is refused', () async {
    await open();
    bloc.add(MoodSelected(MoodType.custom));
    bloc.add(MoodSent());
    await settle();
    expect(states.last, isA<MoodError>());
    expect(repo.sent, isEmpty);
  });

  test('sending reports success when it reached the server', () async {
    await open();
    bloc.add(MoodSelected(MoodType.happy));
    bloc.add(MoodSent());
    await settle();
    expect((states.last as MoodSentSuccess).queued, isFalse);
    expect(repo.sent.single.type, MoodType.happy);
  });

  test('sending offline reports the mood as queued', () async {
    repo.sentNow = false;
    await open();
    bloc.add(MoodSelected(MoodType.sleeping));
    bloc.add(MoodSent());
    await settle();
    expect((states.last as MoodSentSuccess).queued, isTrue);
  });

  test('a rejected send surfaces the error', () async {
    repo.sendError = Exception('rejected');
    await open();
    bloc.add(MoodSelected(MoodType.busy));
    bloc.add(MoodSent());
    await settle();
    expect(states.last, isA<MoodError>());
  });
}
