import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/encryption_state.dart';
import 'package:usync/presentation/features/security/widgets/recovery_phrase_sheet.dart';
import 'package:usync/presentation/features/security/widgets/security_view.dart';

const _code = '12345 67890 11111 22222 33333 44444 55555 66666 77777 88888 99999 00000';
const _phrase = 'legal winner thank year wave sausage worth useful legal winner thank yellow';

void main() {
  // A tall screen by default so buttons are on screen to tap; the overflow tests pass small sizes explicitly.
  Future<void> pump(WidgetTester tester, Widget child, {Size size = const Size(360, 1600), double scale = 1}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
      home: Scaffold(body: child),
    ));
    await tester.pumpAndSettle();
  }

  Widget view(EncryptionState e, {String name = 'Sam', bool busy = false, List<String>? log}) => SecurityView(
        encryption: e,
        partnerName: name,
        busy: busy,
        onVerify: () => log?.add('verify'),
        onApprove: () => log?.add('approve'),
        onSetUpRecovery: () => log?.add('recovery'),
        onRestore: (p) => log?.add('restore:$p'),
        onReset: () => log?.add('reset'),
      );

  const states = {
    'needs verification': EncryptionState(phase: EncryptionPhase.needsVerification, securityCode: _code),
    'ready, nothing done': EncryptionState(phase: EncryptionPhase.ready, securityCode: _code),
    'ready, all done': EncryptionState(phase: EncryptionPhase.ready, securityCode: _code, partnerVerified: true, recoverySetUp: true),
    'partner key changed': EncryptionState(phase: EncryptionPhase.partnerKeyChanged, securityCode: _code),
    'waiting for partner': EncryptionState(phase: EncryptionPhase.waitingForPartner),
    'waiting for key': EncryptionState(phase: EncryptionPhase.waitingForKey, securityCode: _code),
    'needs approval': EncryptionState(phase: EncryptionPhase.needsApproval, securityCode: _code),
    'needs restore': EncryptionState(phase: EncryptionPhase.needsRestore),
    'no couple': EncryptionState(phase: EncryptionPhase.noCouple),
    'unknown': EncryptionState(),
  };

  group('SecurityView', () {
    for (final entry in states.entries) {
      for (final size in const [Size(320, 480), Size(411, 891)]) {
        testWidgets('${entry.key} does not overflow at $size with large text and a long name', (tester) async {
          await pump(tester, view(entry.value, name: 'Alexandria Montgomery-Fitzgerald'), size: size, scale: 1.5);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('shows the security code in groups', (tester) async {
      await pump(tester, view(states['ready, nothing done']!));
      expect(find.text('SECURITY CODE'), findsOneWidget);
      expect(find.textContaining('12345   67890   11111   22222'), findsOneWidget);
      expect(find.text('They match'), findsOneWidget);
    });

    testWidgets('before the code is compared, the page explains that nothing is shared yet and offers "They match"', (tester) async {
      final log = <String>[];
      await pump(tester, view(states['needs verification']!, log: log));
      expect(find.text('Compare your security code'), findsOneWidget);
      expect(find.textContaining('Nothing is shared until'), findsOneWidget);
      await tester.tap(find.text('They match'));
      expect(log, ['verify']);
    });

    testWidgets('"They match" verifies; once verified it says so', (tester) async {
      final log = <String>[];
      await pump(tester, view(states['ready, nothing done']!, log: log));
      await tester.tap(find.text('They match'));
      expect(log, ['verify']);

      await pump(tester, view(states['ready, all done']!, name: 'Sam'));
      expect(find.text('✓ Verified with Sam'), findsOneWidget);
      expect(find.text('They match'), findsNothing);
    });

    testWidgets('a changed partner key offers approval, not plain verification', (tester) async {
      final log = <String>[];
      await pump(tester, view(states['partner key changed']!, log: log));
      expect(find.textContaining('security code changed'), findsOneWidget);
      await tester.tap(find.text('They match: approve'));
      expect(log, ['approve']);
      expect(find.text('They match'), findsNothing);
    });

    testWidgets('the recovery card nags until a phrase is saved', (tester) async {
      final log = <String>[];
      await pump(tester, view(states['ready, nothing done']!, log: log));
      expect(find.textContaining('Not set up'), findsOneWidget);
      await tester.tap(find.text('Set up recovery phrase'));
      expect(log, ['recovery']);

      await pump(tester, view(states['ready, all done']!));
      expect(find.textContaining('Saved ✓'), findsOneWidget);
      expect(find.text('Make a new phrase'), findsOneWidget);
    });

    testWidgets('restoring: the typed phrase is sent, and lost-phrase asks before resetting', (tester) async {
      final log = <String>[];
      await pump(tester, view(states['needs restore']!, log: log));
      expect(find.text('Restore your keys'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'my twelve words');
      await tester.tap(find.text('Restore'));
      expect(log, ['restore:my twelve words']);

      await tester.tap(find.text('I lost my phrase'));
      await tester.pumpAndSettle();
      expect(find.text('Reset your keys?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(log, hasLength(1), reason: 'cancelling does not reset');

      await tester.tap(find.text('I lost my phrase'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      expect(log.last, 'reset');
    });

    testWidgets('while busy the buttons do nothing', (tester) async {
      final log = <String>[];
      await pump(tester, view(states['ready, nothing done']!, busy: true, log: log));
      await tester.tap(find.text('Saving…'));
      await tester.tap(find.text('Set up recovery phrase'));
      expect(log, isEmpty);
    });
  });

  group('RecoveryPhraseSheet', () {
    Future<bool?> open(WidgetTester tester) async {
      bool? result;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const RecoveryPhraseSheet(phrase: _phrase),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('shows all twelve words, numbered', (tester) async {
      await open(tester);
      expect(find.text('1. legal'), findsOneWidget);
      expect(find.text('12. yellow'), findsOneWidget);
      expect(find.text('I have written it down'), findsOneWidget);
    });

    testWidgets('does not overflow on a small screen with large text', (tester) async {
      await pump(tester, const RecoveryPhraseSheet(phrase: _phrase), size: const Size(320, 480), scale: 1.5);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('I have written it down'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('asks for three words; the right ones confirm', (tester) async {
      await pump(tester, const RecoveryPhraseSheet(phrase: _phrase));
      await tester.tap(find.text('I have written it down'));
      await tester.pumpAndSettle();

      final labels = tester.widgetList<Text>(find.textContaining('WORD ')).map((t) => t.data!).toList();
      expect(labels, hasLength(3));
      final words = _phrase.split(' ');
      final fields = find.byType(TextField);
      for (var i = 0; i < 3; i++) {
        final position = int.parse(labels[i].replaceFirst('WORD ', ''));
        await tester.enterText(fields.at(i), words[position - 1].toUpperCase()); // capitals are forgiven
      }
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Check your phrase'), findsNothing, reason: 'the sheet closed with a confirmation');
    });

    testWidgets('wrong words are rejected with a message and the sheet stays', (tester) async {
      await pump(tester, const RecoveryPhraseSheet(phrase: _phrase));
      await tester.tap(find.text('I have written it down'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.enterText(find.byType(TextField).at(i), 'wrong');
      }
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('do not match'), findsOneWidget);
      expect(find.text('Check your phrase'), findsOneWidget);
    });

    testWidgets('you can go back and look at the words again', (tester) async {
      await pump(tester, const RecoveryPhraseSheet(phrase: _phrase));
      await tester.tap(find.text('I have written it down'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show the words again'));
      await tester.pumpAndSettle();
      expect(find.text('1. legal'), findsOneWidget);
    });
  });
}
