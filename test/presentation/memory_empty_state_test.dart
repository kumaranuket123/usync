import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:usync/core/constants/route_names.dart';
import 'package:usync/presentation/features/memory/screens/memory_space_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: RouteNames.memories,
          routes: [
            GoRoute(path: RouteNames.memories, builder: (_, __) => const Scaffold(body: MemoryEmptyState())),
            GoRoute(path: RouteNames.canvas, builder: (_, __) => const Text('canvas opened')),
          ],
        ),
      ));
    // The breathing animation starts on a zero-length timer; let it fire so none is left pending.
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('the one button takes you to the canvas, where memories are made', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Create your first moment ✦'));
    await tester.pumpAndSettle();

    expect(find.text('canvas opened'), findsOneWidget);
  });

  testWidgets('has no button that does nothing', (tester) async {
    await pump(tester);

    expect(find.text('Maybe later'), findsNothing);
  });
}
