import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:usync/core/constants/trust_copy.dart';
import 'package:usync/domain/entities/encryption_state.dart';
import 'package:usync/domain/repositories/i_encryption_repository.dart';
import 'package:usync/presentation/features/onboarding/bloc/onboarding_bloc.dart';
import 'package:usync/presentation/shared/widgets/encryption_badge.dart';
import 'package:usync/presentation/shared/widgets/trust_sheet.dart';

class _Encryption implements IEncryptionRepository {
  _Encryption(this.state);
  EncryptionState state;
  final controller = StreamController<EncryptionState>.broadcast();

  @override
  EncryptionState get current => state;

  @override
  Stream<EncryptionState> get changes => controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {double scale = 1, Size size = const Size(360, 800)}) async {
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

  group('encryptionBadgeFor', () {
    test('claims encryption only when the phone is ready', () {
      for (final phase in EncryptionPhase.values) {
        final info = encryptionBadgeFor(phase);
        expect(info?.label.contains('End-to-end encrypted') ?? false, phase == EncryptionPhase.ready, reason: '$phase');
      }
    });

    test('says nothing until the state is known', () {
      expect(encryptionBadgeFor(EncryptionPhase.unknown), isNull);
    });

    test('asks for action when the person has to do something', () {
      for (final phase in [
        EncryptionPhase.needsVerification,
        EncryptionPhase.needsRestore,
        EncryptionPhase.needsApproval,
        EncryptionPhase.partnerKeyChanged,
      ]) {
        expect(encryptionBadgeFor(phase)!.needsAction, isTrue, reason: '$phase');
      }
      expect(encryptionBadgeFor(EncryptionPhase.waitingForPartner)!.needsAction, isFalse);
    });
  });

  group('EncryptionBadge', () {
    late _Encryption repo;
    setUp(() {
      repo = _Encryption(const EncryptionState());
      GetIt.I.registerSingleton<IEncryptionRepository>(repo);
    });
    tearDown(() => GetIt.I.reset());

    testWidgets('is hidden while unknown, then follows the state', (tester) async {
      await pump(tester, const EncryptionBadge());
      expect(find.textContaining('End-to-end'), findsNothing);

      repo.controller.add(const EncryptionState(phase: EncryptionPhase.needsVerification));
      await tester.pump(); // the stream delivers after the frame
      await tester.pump();
      expect(find.text('Compare your security code'), findsOneWidget);

      repo.controller.add(const EncryptionState(phase: EncryptionPhase.ready));
      await tester.pump();
      await tester.pump();
      expect(find.text('End-to-end encrypted'), findsOneWidget);
    });

    testWidgets('shows the current state at once', (tester) async {
      repo.state = const EncryptionState(phase: EncryptionPhase.ready);
      await pump(tester, const EncryptionBadge());
      expect(find.text('End-to-end encrypted'), findsOneWidget);
    });

    testWidgets('opens the sheet when everything is fine', (tester) async {
      repo.state = const EncryptionState(phase: EncryptionPhase.ready);
      await pump(tester, const EncryptionBadge());
      await tester.tap(find.text('End-to-end encrypted'));
      await tester.pumpAndSettle();
      expect(find.text('🔒 ${TrustCopy.headline}'), findsOneWidget);
    });

    testWidgets('does not overflow on a narrow screen with large text', (tester) async {
      repo.state = const EncryptionState(phase: EncryptionPhase.partnerKeyChanged);
      await pump(tester, const Padding(padding: EdgeInsets.all(16), child: EncryptionBadge()),
          scale: 2, size: const Size(280, 600));
      expect(tester.takeException(), isNull);
    });
  });

  group('trust sheet', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('shows what is encrypted, what is visible and the services at text scale $scale', (tester) async {
        await pump(
          tester,
          Builder(builder: (context) => TextButton(onPressed: () => showTrustSheet(context), child: const Text('open'))),
          scale: scale,
          size: const Size(320, 640),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text(TrustCopy.summary), findsOneWidget);
        expect(find.text('Privacy Policy'), findsOneWidget);
        // Not tied to a signed-in screen, so no shortcut to Security.
        expect(find.text('Check my security code'), findsNothing);
        await tester.scrollUntilVisible(find.text(TrustCopy.promise), 200, scrollable: find.byType(Scrollable).last);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('onboarding', () {
    test('the privacy slide is the last page', () {
      expect(const OnboardingState(currentPage: 3).isLastPage, isFalse);
      expect(const OnboardingState(currentPage: OnboardingState.lastPage).isLastPage, isTrue);
    });
  });
}
