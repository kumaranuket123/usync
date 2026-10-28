import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/mood.dart';
import 'package:usync/domain/entities/mood_insights.dart';

void main() {
  const me = 'me';
  const you = 'you';
  // Wednesday 10 June 2026, 15:00 UTC.
  final now = DateTime.utc(2026, 6, 10, 15);

  Mood mood(String user, MoodType type, DateTime at, {String? label, String? emoji}) =>
      Mood(type: type, userId: user, sentAt: at, customLabel: label, customEmoji: emoji);

  MoodInsights compute(List<Mood> moods) => MoodInsights.compute(moods, userId: me, now: now);

  group('mood groups', () {
    test('warm, calm and busy; custom has none', () {
      expect(MoodType.happy.group, MoodGroup.warm);
      expect(MoodType.thinkingAboutYou.group, MoodGroup.warm);
      expect(MoodType.missingYou.group, MoodGroup.warm);
      expect(MoodType.sleeping.group, MoodGroup.calm);
      expect(MoodType.relaxing.group, MoodGroup.calm);
      expect(MoodType.busy.group, MoodGroup.busy);
      expect(MoodType.custom.group, isNull);
    });

    test('moods feel alike within a group but not across groups', () {
      final t = now;
      expect(mood(me, MoodType.happy, t).feelsLike(mood(you, MoodType.missingYou, t)), isTrue);
      expect(mood(me, MoodType.sleeping, t).feelsLike(mood(you, MoodType.relaxing, t)), isTrue);
      expect(mood(me, MoodType.happy, t).feelsLike(mood(you, MoodType.busy, t)), isFalse);
      expect(mood(me, MoodType.happy, t).feelsLike(mood(you, MoodType.sleeping, t)), isFalse);
    });

    test('custom moods only match the same text, ignoring case and spaces', () {
      final a = mood(me, MoodType.custom, now, label: 'Cozy', emoji: '🧸');
      expect(a.feelsLike(mood(you, MoodType.custom, now, label: ' cozy ', emoji: '🛋️')), isTrue);
      expect(a.feelsLike(mood(you, MoodType.custom, now, label: 'Sad', emoji: '😢')), isFalse);
      expect(a.feelsLike(mood(you, MoodType.happy, now)), isFalse);
      expect(mood(you, MoodType.happy, now).feelsLike(a), isFalse);
    });
  });

  group('MoodInsights.compute', () {
    test('covers seven UTC days, oldest first, ending today', () {
      final i = compute([]);
      expect(i.days, hasLength(7));
      expect(i.days.first.day, DateTime.utc(2026, 6, 4));
      expect(i.days.last.day, DateTime.utc(2026, 6, 10));
      expect(i.isEmpty, isTrue);
      expect(i.inSyncDays, 0);
      expect(i.myTop, isNull);
      expect(i.partnerTop, isNull);
    });

    test('a day is in sync when both shared moods of the same group', () {
      final i = compute([
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 10, 8)),
        mood(you, MoodType.missingYou, DateTime.utc(2026, 6, 10, 9)),
      ]);
      expect(i.days.last.inSync, isTrue);
      expect(i.inSyncDays, 1);
    });

    test('moods from different groups are not in sync', () {
      final i = compute([
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 10, 8)),
        mood(you, MoodType.busy, DateTime.utc(2026, 6, 10, 9)),
      ]);
      expect(i.days.last.bothShared, isTrue);
      expect(i.days.last.inSync, isFalse);
      expect(i.inSyncDays, 0);
    });

    test('the last mood of the day is the one that counts', () {
      final i = compute([
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 10, 6)),
        mood(you, MoodType.missingYou, DateTime.utc(2026, 6, 10, 7)),
        mood(you, MoodType.busy, DateTime.utc(2026, 6, 10, 12)),
      ]);
      expect(i.days.last.partner!.type, MoodType.busy);
      expect(i.days.last.inSync, isFalse);
    });

    test('a day where only one partner shared is shared by one, not in sync', () {
      final i = compute([mood(me, MoodType.happy, DateTime.utc(2026, 6, 9, 10))]);
      final d = i.days[5];
      expect(d.mine, isNotNull);
      expect(d.partner, isNull);
      expect(d.bothShared, isFalse);
      expect(d.inSync, isFalse);
      expect(i.isEmpty, isFalse);
    });

    test('days are UTC days: 23:59 and 00:01 UTC fall on different days', () {
      final i = compute([
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 8, 23, 59)),
        mood(you, MoodType.happy, DateTime.utc(2026, 6, 9, 0, 1)),
      ]);
      expect(i.inSyncDays, 0, reason: 'one minute apart but on different UTC days');
      expect(i.days[4].mine, isNotNull);
      expect(i.days[5].partner, isNotNull);
    });

    test('a time given in another zone is placed by its UTC day', () {
      // 01:30 on the 10th at UTC+5:30 is 20:00 UTC on the 9th.
      final local = DateTime.parse('2026-06-10T01:30:00+05:30');
      final i = compute([mood(me, MoodType.happy, local)]);
      expect(i.days[5].mine, isNotNull);
      expect(i.days[6].mine, isNull);
    });

    test('moods outside the window or in the future are ignored', () {
      final i = compute([
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 3, 23, 59)), // the day before the window
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 11, 0, 1)),  // tomorrow
      ]);
      expect(i.isEmpty, isTrue);
    });

    test('the first and last days of the window are included', () {
      final i = compute([
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 4, 0, 0)),
        mood(me, MoodType.busy, DateTime.utc(2026, 6, 10, 23, 59)),
      ]);
      expect(i.days.first.mine!.type, MoodType.happy);
      expect(i.days.last.mine!.type, MoodType.busy);
    });

    test('custom moods are in sync only on the same text', () {
      final same = compute([
        mood(me, MoodType.custom, DateTime.utc(2026, 6, 10, 8), label: 'Cozy', emoji: '🧸'),
        mood(you, MoodType.custom, DateTime.utc(2026, 6, 10, 9), label: 'cozy', emoji: '🛋️'),
      ]);
      expect(same.inSyncDays, 1);

      final different = compute([
        mood(me, MoodType.custom, DateTime.utc(2026, 6, 10, 8), label: 'Cozy', emoji: '🧸'),
        mood(you, MoodType.custom, DateTime.utc(2026, 6, 10, 9), label: 'Tired', emoji: '🥱'),
      ]);
      expect(different.inSyncDays, 0);
    });

    test('moods arriving in any order give the same answer', () {
      final moods = [
        mood(you, MoodType.missingYou, DateTime.utc(2026, 6, 10, 9)),
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 10, 8)),
      ];
      expect(compute(moods), compute(moods.reversed.toList()));
    });
  });

  group('most shared mood', () {
    test('is the one shared most often, per person', () {
      final i = compute([
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 6, 8)),
        mood(me, MoodType.busy, DateTime.utc(2026, 6, 7, 8)),
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 8, 8)),
        mood(you, MoodType.sleeping, DateTime.utc(2026, 6, 9, 8)),
      ]);
      expect(i.myTop!.type, MoodType.happy);
      expect(i.partnerTop!.type, MoodType.sleeping);
    });

    test('counts every mood, not just the last of each day', () {
      final i = compute([
        mood(me, MoodType.busy, DateTime.utc(2026, 6, 9, 6)),
        mood(me, MoodType.busy, DateTime.utc(2026, 6, 9, 7)),
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 9, 20)),
      ]);
      expect(i.myTop!.type, MoodType.busy);
    });

    test('a tie goes to the most recent mood', () {
      final i = compute([
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 8, 8)),
        mood(me, MoodType.relaxing, DateTime.utc(2026, 6, 9, 8)),
      ]);
      expect(i.myTop!.type, MoodType.relaxing);
    });

    test('custom moods are counted by their text', () {
      final i = compute([
        mood(me, MoodType.custom, DateTime.utc(2026, 6, 8, 8), label: 'Cozy', emoji: '🧸'),
        mood(me, MoodType.custom, DateTime.utc(2026, 6, 9, 8), label: 'cozy', emoji: '🧸'),
        mood(me, MoodType.happy, DateTime.utc(2026, 6, 9, 9)),
      ]);
      expect(i.myTop!.label.toLowerCase(), 'cozy');
    });
  });
}
