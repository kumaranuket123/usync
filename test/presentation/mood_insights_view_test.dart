import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/mood.dart';
import 'package:usync/domain/entities/mood_insights.dart';
import 'package:usync/presentation/features/mood_insights/widgets/mood_insights_view.dart';

void main() {
  final now = DateTime.utc(2026, 6, 10, 15);

  MoodInsights insights(List<Mood> moods) => MoodInsights.compute(moods, userId: 'me', now: now);

  Future<void> pump(WidgetTester tester, MoodInsights i, {Size size = const Size(360, 640), double scale = 1, String name = 'Sam'}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: MoodInsightsView(insights: i, partnerName: name)),
    ));
    await tester.pumpAndSettle();
  }

  final withData = insights([
    for (var d = 4; d <= 10; d++) ...[
      Mood(type: MoodType.happy, userId: 'me', sentAt: DateTime.utc(2026, 6, d, 8)),
      Mood(type: d.isEven ? MoodType.missingYou : MoodType.busy, userId: 'you', sentAt: DateTime.utc(2026, 6, d, 9)),
    ],
    Mood(type: MoodType.custom, userId: 'me', sentAt: DateTime.utc(2026, 6, 10, 20), customLabel: 'Feeling extremely cozy and warm today', customEmoji: '🧸'),
  ]);

  testWidgets('shows the in-sync count, the strip and the most shared moods', (tester) async {
    await pump(tester, withData);

    expect(find.textContaining('of the last 7 days'), findsOneWidget);
    expect(find.text('💞'), findsWidgets);
    expect(find.text('You shared most'), findsOneWidget);
    expect(find.text('Sam shared most'), findsOneWidget);
    expect(find.textContaining('UTC'), findsOneWidget);
  });

  testWidgets('with nobody having shared a mood it invites you to share one', (tester) async {
    await pump(tester, insights([]));

    expect(find.text('Nothing to show yet'), findsOneWidget);
    expect(find.textContaining('Share a mood'), findsOneWidget);
  });

  for (final size in const [Size(320, 480), Size(411, 891)]) {
    for (final (label, data) in [('with data', withData), ('empty', insights([]))]) {
      testWidgets('does not overflow $label at $size with large text and a long name', (tester) async {
        await pump(tester, data, size: size, scale: 1.5, name: 'Alexandria Montgomery-Fitzgerald');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
