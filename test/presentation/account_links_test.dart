import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usync/presentation/features/settings/widgets/account_links.dart';
import 'package:usync/presentation/features/settings/widgets/delete_account_dialog.dart';

void main() {
  testWidgets('account links offer About, Privacy Policy and Delete account', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AccountLinks())));

    expect(find.text('About Usync'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
  });

  group('DeleteAccountDialog', () {
    Future<Future<bool?>> open(WidgetTester tester) async {
      late Future<bool?> result;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory), // the ripple shader cannot load in tests
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => result = showDialog<bool>(context: context, builder: (_) => const DeleteAccountDialog()),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    TextButton deleteButton(WidgetTester tester) =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Delete'));

    testWidgets('Delete stays disabled until DELETE is typed', (tester) async {
      await open(tester);
      expect(deleteButton(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'delet');
      await tester.pump();
      expect(deleteButton(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'delete'); // any case is accepted
      await tester.pump();
      expect(deleteButton(tester).onPressed, isNotNull);
    });

    testWidgets('confirming returns true, cancelling returns false', (tester) async {
      var result = await open(tester);
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);

      result = await open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });
}
