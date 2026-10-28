import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/crypto_service.dart';
import 'package:usync/domain/entities/encryption_state.dart';
import 'package:usync/domain/repositories/i_encryption_repository.dart';
import 'package:usync/presentation/features/security/bloc/security_bloc.dart';

class _FakeEncryption implements IEncryptionRepository {
  EncryptionState state = const EncryptionState(phase: EncryptionPhase.ready, securityCode: '11111 22222 33333 44444 55555 66666 77777 88888 99999 00000 11111 22222');
  EncryptionState? syncResult;
  Object? restoreError;
  Object? verifyError;
  final calls = <String>[];

  @override
  EncryptionState get current => state;

  @override
  Future<EncryptionState> sync() async {
    calls.add('sync');
    return syncResult ?? state;
  }

  @override
  Future<EncryptionState> markPartnerVerified(String securityCode) async {
    calls.add('verify:$securityCode');
    if (verifyError != null) throw verifyError!;
    return state = EncryptionState(phase: state.phase, securityCode: state.securityCode, partnerVerified: true, recoverySetUp: state.recoverySetUp);
  }

  @override
  String newRecoveryPhrase() => 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  @override
  Future<EncryptionState> finishRecovery(String phrase) async {
    calls.add('recovery:$phrase');
    return state = EncryptionState(phase: state.phase, securityCode: state.securityCode, recoverySetUp: true);
  }

  @override
  Future<EncryptionState> restoreWithPhrase(String phrase) async {
    calls.add('restore:$phrase');
    if (restoreError != null) throw restoreError!;
    return state = const EncryptionState(phase: EncryptionPhase.ready, recoverySetUp: true);
  }

  @override
  Future<EncryptionState> resetKeys() async {
    calls.add('reset');
    return state = const EncryptionState(phase: EncryptionPhase.waitingForKey);
  }

  @override
  Future<EncryptionState> startFresh() async {
    calls.add('fresh');
    return state = const EncryptionState(phase: EncryptionPhase.ready);
  }

  @override
  Future<EncryptionState> approvePartnerKey(String securityCode) async {
    calls.add('approve:$securityCode');
    return state = const EncryptionState(phase: EncryptionPhase.ready);
  }
}

void main() {
  late _FakeEncryption repo;
  late SecurityBloc bloc;

  setUp(() {
    repo = _FakeEncryption();
    bloc = SecurityBloc(encryptionRepository: repo);
  });

  tearDown(() => bloc.close());

  Future<SecurityReady> open() async {
    bloc.add(const SecurityOpened());
    return await bloc.stream.firstWhere((s) => s is SecurityReady) as SecurityReady;
  }

  Future<SecurityReady> next() async => await bloc.stream.firstWhere((s) => s is SecurityReady && !s.busy) as SecurityReady;

  test('opening loads the current state', () async {
    final s = await open();
    expect(s.encryption.phase, EncryptionPhase.ready);
    expect(s.notice, isNull);
  });

  test('if the server cannot be reached the page says so, and keeps what it knew', () async {
    await open();
    repo.syncResult = const EncryptionState.unknown();
    bloc.add(const SecurityOpened());
    final s = await next();
    expect(s.encryption.phase, EncryptionPhase.ready, reason: 'not replaced by "unknown"');
  });

  test('a first open with no connection shows the unknown state and a notice', () async {
    repo.syncResult = const EncryptionState.unknown();
    final s = await open();
    expect(s.encryption.phase, EncryptionPhase.unknown);
    expect(s.notice, contains('connection'));
  });

  test('verifying sends the exact code the person was looking at, and confirms', () async {
    await open();
    final shown = repo.state.securityCode!;
    bloc.add(PartnerVerifiedMarked(shown));
    final s = await bloc.stream.firstWhere((s) => s is SecurityReady && !s.busy && s.notice != null) as SecurityReady;
    expect(repo.calls, contains('verify:$shown'));
    expect(s.encryption.partnerVerified, isTrue);
  });

  test('if the code changed while they were looking, they are told and the page refreshes', () async {
    await open();
    repo.verifyError = const CryptoException('The security code changed while you were looking at it. Compare the new code.');
    bloc.add(const PartnerVerifiedMarked('stale code'));
    final s = await bloc.stream.firstWhere((s) => s is SecurityReady && s.notice != null && !s.busy) as SecurityReady;
    expect(s.notice, contains('changed while you were looking'));
    expect(s.encryption.partnerVerified, isFalse);
    await pumpEventQueue();
    expect(repo.calls.where((c) => c == 'sync').length, greaterThan(1), reason: 'the page re-reads the current code');
  });

  test('approving the partner\'s new key goes to the repository', () async {
    repo.state = const EncryptionState(phase: EncryptionPhase.partnerKeyChanged);
    await open();
    bloc.add(const PartnerKeyApproved('the code on screen'));
    await bloc.stream.firstWhere((s) => s is SecurityReady && s.encryption.phase == EncryptionPhase.ready);
    expect(repo.calls, contains('approve:the code on screen'));
  });

  group('recovery phrase', () {
    test('asking shows a phrase, confirming stores the backup and clears it', () async {
      await open();
      bloc.add(const RecoveryPhraseRequested());
      final shown = await bloc.stream.firstWhere((s) => s is SecurityReady && s.phraseToShow != null) as SecurityReady;
      expect(shown.phraseToShow!.split(' '), hasLength(12));

      bloc.add(RecoveryPhraseConfirmed(shown.phraseToShow!));
      final done = await bloc.stream.firstWhere((s) => s is SecurityReady && s.encryption.recoverySetUp) as SecurityReady;

      expect(repo.calls, contains('recovery:${shown.phraseToShow}'));
      expect(done.phraseToShow, isNull);
    });

    test('closing the sheet without confirming forgets the phrase and saves nothing', () async {
      await open();
      bloc.add(const RecoveryPhraseRequested());
      await bloc.stream.firstWhere((s) => s is SecurityReady && s.phraseToShow != null);
      bloc.add(const RecoveryPhraseDismissed());
      final s = await bloc.stream.firstWhere((s) => s is SecurityReady && s.phraseToShow == null) as SecurityReady;
      expect(s.encryption.recoverySetUp, isFalse);
      expect(repo.calls.where((c) => c.startsWith('recovery')), isEmpty);
    });

    test('a failed save keeps the phrase on screen so the person can try again', () async {
      await open();
      bloc.add(const RecoveryPhraseRequested());
      await bloc.stream.firstWhere((s) => s is SecurityReady && s.phraseToShow != null);
      repo.syncResult = null;
      repo.state = const EncryptionState.unknown();
      bloc.add(const RecoveryPhraseConfirmed('x'));
      final s = await bloc.stream.firstWhere((s) => s is SecurityReady && s.notice != null) as SecurityReady;
      expect(s.phraseToShow, isNotNull);
      expect(s.notice, contains('did not finish'));
    });
  });

  group('restoring', () {
    test('the right phrase brings the keys back', () async {
      repo.state = const EncryptionState(phase: EncryptionPhase.needsRestore);
      await open();
      bloc.add(const RestoreSubmitted('the phrase'));
      final s = await bloc.stream.firstWhere((s) => s is SecurityReady && s.encryption.phase == EncryptionPhase.ready) as SecurityReady;
      expect(repo.calls, contains('restore:the phrase'));
      expect(s.notice, contains('back'));
    });

    test('a wrong phrase shows why, and changes nothing', () async {
      repo.state = const EncryptionState(phase: EncryptionPhase.needsRestore);
      await open();
      repo.restoreError = const CryptoException('That is not a valid 12-word recovery phrase');
      bloc.add(const RestoreSubmitted('nope'));
      final s = await bloc.stream.firstWhere((s) => s is SecurityReady && s.notice != null && !s.busy) as SecurityReady;
      expect(s.notice, contains('not a valid'));
      expect(s.encryption.phase, EncryptionPhase.needsRestore);
    });

    test('an unexpected error gives a generic message', () async {
      repo.state = const EncryptionState(phase: EncryptionPhase.needsRestore);
      await open();
      repo.restoreError = Exception('boom');
      bloc.add(const RestoreSubmitted('x'));
      final s = await bloc.stream.firstWhere((s) => s is SecurityReady && s.notice != null && !s.busy) as SecurityReady;
      expect(s.notice, contains('Something went wrong'));
      expect(s.notice, isNot(contains('boom')), reason: 'internal details are not shown');
    });
  });

  test('resetting the keys goes to the repository and explains what happens next', () async {
    await open();
    bloc.add(const KeysResetRequested());
    final s = await bloc.stream.firstWhere((s) => s is SecurityReady && s.encryption.phase == EncryptionPhase.waitingForKey) as SecurityReady;
    expect(repo.calls, contains('reset'));
    expect(s.notice, contains('approve'));
  });
}
