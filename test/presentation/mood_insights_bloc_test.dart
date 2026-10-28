import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/couple.dart';
import 'package:usync/domain/entities/mood.dart';
import 'package:usync/domain/entities/user.dart';
import 'package:usync/domain/repositories/i_auth_repository.dart';
import 'package:usync/domain/repositories/i_couple_repository.dart';
import 'package:usync/domain/repositories/i_mood_repository.dart';
import 'package:usync/presentation/features/mood_insights/bloc/mood_insights_bloc.dart';

class _FakeMoods implements IMoodRepository {
  List<Mood> moods = [];
  bool fails = false;
  DateTime? askedSince;

  @override
  Future<List<Mood>> getMoodsSince(String coupleId, DateTime since) async {
    askedSince = since;
    if (fails) throw Exception('offline');
    return moods;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCouples implements ICoupleRepository {
  bool fails = false;
  @override
  Future<Couple> getCouple(String coupleId) async {
    if (fails) throw Exception('offline');
    return Couple(id: coupleId, userAId: 'me', userBId: 'you', pairedAt: DateTime(2026));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements IAuthRepository {
  String? partnerName = 'Sam';
  @override
  Future<AppUser?> getUserById(String uid) async => partnerName == null
      ? null
      : AppUser(id: uid, username: partnerName!, email: '', avatarEmoji: '🦋', createdAt: DateTime(2026));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeMoods moods;
  late _FakeCouples couples;
  late _FakeAuth auth;
  late MoodInsightsBloc bloc;
  final now = DateTime.utc(2026, 6, 10, 15);

  setUp(() {
    moods = _FakeMoods();
    couples = _FakeCouples();
    auth = _FakeAuth();
    bloc = MoodInsightsBloc(moodRepository: moods, coupleRepository: couples, authRepository: auth, clock: () => now);
  });

  tearDown(() => bloc.close());

  Future<MoodInsightsState> open() async {
    bloc.add(InsightsOpened(coupleId: 'c', userId: 'me'));
    return bloc.stream.firstWhere((s) => s is! InsightsLoading);
  }

  test('loads a week of moods and works out the insights', () async {
    moods.moods = [
      Mood(type: MoodType.happy, userId: 'me', sentAt: DateTime.utc(2026, 6, 10, 8)),
      Mood(type: MoodType.missingYou, userId: 'you', sentAt: DateTime.utc(2026, 6, 10, 9)),
    ];

    final s = await open() as InsightsReady;

    expect(moods.askedSince, DateTime.utc(2026, 6, 4), reason: 'seven UTC days, today included');
    expect(s.insights.inSyncDays, 1);
    expect(s.partnerName, 'Sam');
  });

  test('with no moods the insights are empty', () async {
    final s = await open() as InsightsReady;
    expect(s.insights.isEmpty, isTrue);
  });

  test('a failed load reports an error', () async {
    moods.fails = true;
    final s = await open();
    expect(s, isA<InsightsError>());
  });

  test('if the partner cannot be looked up the insights still show, with a generic name', () async {
    couples.fails = true;
    expect((await open() as InsightsReady).partnerName, 'Your partner');
  });

  test('a partner with no name falls back to a generic one', () async {
    auth.partnerName = null;
    expect((await open() as InsightsReady).partnerName, 'Your partner');
  });
}
