import 'package:equatable/equatable.dart';

import 'mood.dart';

/// One UTC day: the last mood each partner shared that day (null when they shared none).
class MoodDay extends Equatable {
  const MoodDay({required this.day, this.mine, this.partner});

  /// UTC midnight of the day, the same day boundary the day streak uses.
  final DateTime day;
  final Mood?    mine;
  final Mood?    partner;

  bool get bothShared => mine != null && partner != null;
  bool get inSync     => bothShared && mine!.feelsLike(partner!);

  @override
  List<Object?> get props => [day, mine, partner];
}

/// How in sync a couple has been over the last few days.
class MoodInsights extends Equatable {
  const MoodInsights({required this.days, this.myTop, this.partnerTop});

  /// Oldest first; the last one is today (UTC).
  final List<MoodDay> days;
  /// The mood each person shared most often in the window (the most recent one on a tie).
  final Mood? myTop;
  final Mood? partnerTop;

  int  get inSyncDays => days.where((d) => d.inSync).length;
  /// Nobody shared a mood in the window.
  bool get isEmpty    => days.every((d) => d.mine == null && d.partner == null);

  /// [moods] are the couple's moods in any order; [userId] is "mine", anyone else is the partner.
  /// Days are UTC days, so partners in different time zones are compared on the same day.
  factory MoodInsights.compute(List<Mood> moods, {required String userId, required DateTime now, int days = 7}) {
    final nowUtc = now.toUtc();
    final today  = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final first  = today.subtract(Duration(days: days - 1));
    final end    = today.add(const Duration(days: 1));

    final inWindow = moods.where((m) {
      final t = m.sentAt.toUtc();
      return !t.isBefore(first) && t.isBefore(end);
    }).toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));

    final dayList = <MoodDay>[
      for (var i = 0; i < days; i++)
        () {
          final day = first.add(Duration(days: i));
          final next = day.add(const Duration(days: 1));
          Mood? lastOf(bool mine) {
            Mood? last;
            for (final m in inWindow) {
              final t = m.sentAt.toUtc();
              if ((m.userId == userId) == mine && !t.isBefore(day) && t.isBefore(next)) last = m;
            }
            return last;
          }
          return MoodDay(day: day, mine: lastOf(true), partner: lastOf(false));
        }(),
    ];

    return MoodInsights(
      days:       dayList,
      myTop:      _topMood(inWindow.where((m) => m.userId == userId)),
      partnerTop: _topMood(inWindow.where((m) => m.userId != userId)),
    );
  }

  static Mood? _topMood(Iterable<Mood> moods) {
    final counts = <String, int>{};
    final latest = <String, Mood>{};
    for (final m in moods) {
      counts.update(m.countKey, (c) => c + 1, ifAbsent: () => 1);
      latest[m.countKey] = m; // moods arrive oldest first, so the last one wins
    }
    if (counts.isEmpty) return null;
    final best = counts.values.reduce((a, b) => a > b ? a : b);
    final tied = counts.entries.where((e) => e.value == best).map((e) => latest[e.key]!).toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return tied.last;
  }

  @override
  List<Object?> get props => [days, myTop, partnerTop];
}
