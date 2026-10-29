import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:usync/presentation/features/settings/screens/about_screen.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Usync', packageName: 'app.usync', version: '1.2.3', buildNumber: '45',
      buildSignature: '',
    );
  });

  Future<void> pump(WidgetTester tester, {double scale = 1.0, Size size = const Size(360, 640)}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const AboutScreen(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the app, its version and every feature section', (tester) async {
    await pump(tester);

    expect(find.text('Usync'), findsOneWidget);
    expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
    for (final section in ['CONNECT', 'CREATE AND REMEMBER', 'NEAR OR FAR', 'ALWAYS WITH YOU', 'PRIVATE BY DESIGN']) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
  });

  testWidgets('describes the features the app has', (tester) async {
    await pump(tester);

    for (final feature in [
      'Pairing', 'Touch sync', 'Moods', 'Mood insights', 'Question of the day', 'Couple games', 'Shared canvas', 'Memories', 'Timeline',
      'Bucket list', 'Streaks', 'Relationship type', 'Long-distance card', 'Location', 'Notifications',
      'Home-screen widget', 'Works offline', 'Themes', 'App lock', 'Only the two of you', 'You are in control',
    ]) {
      expect(find.text(feature), findsOneWidget, reason: feature);
    }
    expect(find.text('Read our Privacy Policy'), findsOneWidget);
  });

  for (final size in const [Size(320, 480), Size(411, 891)]) {
    testWidgets('does not overflow at $size with large text', (tester) async {
      await pump(tester, scale: 1.5, size: size);
      expect(tester.takeException(), isNull);
    });
  }
}
