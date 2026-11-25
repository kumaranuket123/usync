import 'package:flutter_test/flutter_test.dart';
import 'package:usync/presentation/features/chat/screens/chat_screen.dart';

void main() {
  final now = DateTime(2026, 11, 25, 15);

  test('today and yesterday are named, other days show the date', () {
    expect(dayLabel(DateTime(2026, 11, 25, 0, 1), now: now), 'Today');
    expect(dayLabel(DateTime(2026, 11, 24, 23, 59), now: now), 'Yesterday');
    expect(dayLabel(DateTime(2026, 11, 12, 9), now: now), '12 Nov');
  });

  test('a day in another year includes the year', () {
    expect(dayLabel(DateTime(2025, 12, 31, 9), now: now), '31 Dec 2025');
  });

  test('the day is the phone\'s local day, also across a month end', () {
    expect(dayLabel(DateTime(2026, 10, 31, 12), now: DateTime(2026, 11, 1, 8)), 'Yesterday');
  });
}
