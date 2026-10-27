import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/utils/app_snack_bar.dart';

void main() {
  Future<void> show(WidgetTester tester, {SnackBarAction? action}) async {
    await tester.pumpWidget(MaterialApp(
      // No ripple: its shader asset cannot be loaded by the test runner.
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              appSnackBar(content: const Text('Hello there'), action: action),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // slide in
    expect(find.text('Hello there'), findsOneWidget);
  }

  testWidgets('goes away by itself', (tester) async {
    await show(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Hello there'), findsNothing);
  });

  testWidgets('goes away by itself even with an action button', (tester) async {
    await show(tester, action: SnackBarAction(label: 'View', onPressed: () {}));
    expect(find.text('View'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Hello there'), findsNothing);
  });

  for (final (name, offset) in [
    ('left', const Offset(-400, 0)),
    ('right', const Offset(400, 0)),
    ('down', const Offset(0, 300)),
  ]) {
    testWidgets('can be swiped away to the $name', (tester) async {
      await show(tester);
      await tester.fling(find.text('Hello there'), offset, 1500);
      await tester.pumpAndSettle();
      expect(find.text('Hello there'), findsNothing);
    });
  }
}
