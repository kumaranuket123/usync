import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/services/reminder_service.dart';
import 'package:usync/domain/entities/milestone.dart';

class _FakeScheduler implements ReminderScheduler {
  final events = <String>[];
  final scheduled = <Reminder>[];

  @override
  Future<void> cancelAll() async => events.add('cancel');

  @override
  Future<void> schedule(Reminder r) async {
    events.add('schedule');
    scheduled.add(r);
  }
}

Milestone date(String id, DateTime day, {bool yearly = false, String title = 'Anniversary', String emoji = '🎂', MilestoneType type = MilestoneType.custom}) => Milestone(
      id: id,
      coupleId: 'c1',
      type: type,
      title: title,
      emoji: emoji,
      occurredAt: DateTime.utc(day.year, day.month, day.day, 12),
      repeatsYearly: yearly,
    );

void main() {
  final now = DateTime(2026, 10, 28, 10); // after 9:00 today

  group('plan', () {
    test('a one-off date in the future is reminded at 9:00 on its day', () {
      final plan = ReminderService.plan([date('a', DateTime(2026, 12, 25))], now);

      expect(plan, hasLength(1));
      expect(plan.single.when, DateTime(2026, 12, 25, 9));
      expect(plan.single.title, '🎂 Anniversary');
      expect(plan.single.body, 'Today 💖');
    });

    test('a one-off date that has passed, or whose 9:00 has passed today, is not scheduled', () {
      final plan = ReminderService.plan([date('a', DateTime(2026, 3, 1)), date('b', DateTime(2026, 10, 28))], now);
      expect(plan, isEmpty);
    });

    test('a date today before 9:00 is still reminded', () {
      final early = DateTime(2026, 10, 28, 8);
      expect(ReminderService.plan([date('a', DateTime(2026, 10, 28))], early).single.when, DateTime(2026, 10, 28, 9));
    });

    test('a yearly date gets its next three anniversaries, each with its own count', () {
      final plan = ReminderService.plan([date('a', DateTime(2023, 11, 5), yearly: true)], now);

      expect(plan.map((r) => r.when), [DateTime(2026, 11, 5, 9), DateTime(2027, 11, 5, 9), DateTime(2028, 11, 5, 9)]);
      expect(plan.map((r) => r.body), ['3 years today! 💖', '4 years today! 💖', '5 years today! 💖']);
    });

    test('the first anniversary says "1 year", and a yearly date still ahead says "Today"', () {
      final first = ReminderService.plan([date('a', DateTime(2025, 12, 1), yearly: true)], now);
      expect(first.first.body, '1 year today! 💖');

      final future = ReminderService.plan([date('b', DateTime(2026, 12, 1), yearly: true)], now);
      expect(future.first.when, DateTime(2026, 12, 1, 9));
      expect(future.first.body, 'Today 💖');
    });

    test('a yearly date whose day is today but after 9:00 moves to next year', () {
      final plan = ReminderService.plan([date('a', DateTime(2020, 10, 28), yearly: true)], now);
      expect(plan.first.when, DateTime(2027, 10, 28, 9));
      expect(plan.first.body, '7 years today! 💖');
    });

    test('29 February is reminded on the 28th in years without one', () {
      final plan = ReminderService.plan([date('a', DateTime(2020, 2, 29), yearly: true)], DateTime(2026, 10, 28, 10));
      expect(plan.map((r) => r.when), [DateTime(2027, 2, 28, 9), DateTime(2028, 2, 29, 9), DateTime(2029, 2, 28, 9)]);
    });

    test('only custom dates the phone could read are reminded', () {
      final plan = ReminderService.plan([
        date('streak', DateTime(2026, 12, 1), type: MilestoneType.streak7),
        date('locked', DateTime(1970, 1, 1)),
        date('ok', DateTime(2026, 12, 2)),
      ], now);
      expect(plan.map((r) => r.when), [DateTime(2026, 12, 2, 9)]);
    });

    test('reminders are in time order with unique ids, and capped', () {
      final many = [for (var i = 0; i < 40; i++) date('m$i', DateTime(2023, 1 + i % 12, 1 + i % 20), yearly: true)];
      final plan = ReminderService.plan(many, now);

      expect(plan.length, 60);
      expect({for (final r in plan) r.id}.length, 60);
      for (var i = 1; i < plan.length; i++) {
        expect(!plan[i].when.isBefore(plan[i - 1].when), isTrue);
      }
    });
  });

  group('schedule', () {
    test('clears what was scheduled, then schedules the plan', () async {
      final scheduler = _FakeScheduler();
      final service = ReminderService(scheduler: scheduler, now: () => now);

      await service.schedule([date('a', DateTime(2026, 12, 25))]);

      expect(scheduler.events, ['cancel', 'schedule']);
    });

    test('with no dates it only clears (a date that was deleted stops reminding)', () async {
      final scheduler = _FakeScheduler();
      await ReminderService(scheduler: scheduler, now: () => now).schedule(const []);
      expect(scheduler.events, ['cancel']);
    });

    test('cancelAll removes everything', () async {
      final scheduler = _FakeScheduler();
      await ReminderService(scheduler: scheduler).cancelAll();
      expect(scheduler.events, ['cancel']);
    });
  });
}
