import 'package:flutter_test/flutter_test.dart';
import 'package:usync/data/models/couple_model.dart';

void main() {
  Map<String, dynamic> row({String? lastDay, int streak = 5}) => {
        'id': 'c1',
        'user_a_id': 'a',
        'user_b_id': 'b',
        'paired_at': '2026-01-01T00:00:00Z',
        'streak_days': streak,
        'streak_last_day': lastDay,
        'total_moments': 12,
      };

  String day(Duration ago) {
    final d = DateTime.now().toUtc().subtract(ago);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  test('parses a couple row', () {
    final couple = CoupleModel.fromRow(row(lastDay: day(Duration.zero)));
    expect(couple.id, 'c1');
    expect(couple.totalMoments, 12);
    expect(couple.isDisconnected, isFalse);
  });

  test('a streak active today or yesterday is kept', () {
    expect(CoupleModel.fromRow(row(lastDay: day(Duration.zero))).streakDays, 5);
    expect(CoupleModel.fromRow(row(lastDay: day(const Duration(days: 1)))).streakDays, 5);
  });

  test('a streak older than yesterday has already ended', () {
    expect(CoupleModel.fromRow(row(lastDay: day(const Duration(days: 2)))).streakDays, 0);
  });

  test('no activity day means no streak', () {
    expect(CoupleModel.fromRow(row()).streakDays, 0);
  });

  test('a deleted partner (null id) becomes an empty id and the couple shows as disconnected', () {
    final couple = CoupleModel.fromRow({
      ...row(),
      'user_b_id': null,
      'disconnected_at': '2026-02-01T00:00:00Z',
    });
    expect(couple.userBId, '');
    expect(couple.isDisconnected, isTrue);
  });

  test('partnerIdFor returns the other member', () {
    final couple = CoupleModel.fromRow(row());
    expect(couple.partnerIdFor('a'), 'b');
    expect(couple.partnerIdFor('b'), 'a');
  });
}
