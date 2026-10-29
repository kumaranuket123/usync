import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:usync/core/constants/route_names.dart';
import 'package:usync/presentation/features/activity/screens/activity_screen.dart';

void main() {
  Future<GoRouter> pump(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: RouteNames.activity,
      routes: [
        GoRoute(path: RouteNames.activity, builder: (_, __) => const ActivityScreen()),
        for (final path in [RouteNames.games, RouteNames.bucketList, RouteNames.timeline])
          GoRoute(path: path, builder: (_, __) => Text('opened $path')),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    return router;
  }

  testWidgets('lists couple games, bucket list and the relationship timeline', (tester) async {
    await pump(tester);

    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Couple games'), findsOneWidget);
    expect(find.text('Bucket list'), findsOneWidget);
    expect(find.text('Relationship timeline'), findsOneWidget);
  });

  testWidgets('says more is coming soon, and the banner is not tappable', (tester) async {
    final router = await pump(tester);

    expect(find.text('More coming soon'), findsOneWidget);
    await tester.tap(find.text('More coming soon'));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, RouteNames.activity);
  });

  for (final (title, route) in [
    ('Couple games', RouteNames.games),
    ('Bucket list', RouteNames.bucketList),
    ('Relationship timeline', RouteNames.timeline),
  ]) {
    testWidgets('$title opens $route', (tester) async {
      await pump(tester);

      await tester.tap(find.text(title));
      await tester.pumpAndSettle();

      expect(find.text('opened $route'), findsOneWidget);
    });
  }

  testWidgets('does not overflow on a small screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await pump(tester);

    expect(tester.takeException(), isNull);
  });
}
