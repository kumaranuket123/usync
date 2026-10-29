import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usync/presentation/features/profile/widgets/sign_out_button.dart';

void main() {
  Future<List<int>> pump(WidgetTester tester) async {
    final calls = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SignOutButton(onConfirmed: () => calls.add(1))),
    ));
    return calls;
  }

  testWidgets('asks first, and signs out only after confirming', (tester) async {
    final calls = await pump(tester);

    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Sign Out')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
  });

  testWidgets('cancelling keeps the person signed in', (tester) async {
    final calls = await pump(tester);

    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsNothing);
    expect(calls, isEmpty);
  });
}
