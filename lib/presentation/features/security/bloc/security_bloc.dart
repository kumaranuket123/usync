import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/crypto/crypto_service.dart';
import '../../../../domain/entities/encryption_state.dart';
import '../../../../domain/repositories/i_encryption_repository.dart';

part 'security_event.dart';
part 'security_state.dart';

class SecurityBloc extends Bloc<SecurityEvent, SecurityState> {
  SecurityBloc({required this.encryptionRepository}) : super(const SecurityLoading()) {
    on<SecurityOpened>((_, emit) => _refresh(emit));
    on<SecurityRefreshed>((_, emit) => _refresh(emit, quiet: true));
    on<PartnerVerifiedMarked>((e, emit) => _run(emit, () => encryptionRepository.markPartnerVerified(e.securityCode), done: 'Marked as verified'));
    on<PartnerKeyApproved>((e, emit) => _run(emit, () => encryptionRepository.approvePartnerKey(e.securityCode), done: 'Approved. Your partner can read again.'));
    on<RecoveryPhraseRequested>(_onPhraseRequested);
    on<RecoveryPhraseDismissed>((_, emit) {
      final ready = _ready;
      if (ready != null) emit(ready.copyWith(clearPhrase: true));
    });
    on<RecoveryPhraseConfirmed>((e, emit) => _run(emit, () => encryptionRepository.finishRecovery(e.phrase), done: 'Recovery phrase saved', clearPhrase: true));
    on<RestoreSubmitted>(_onRestore);
    on<KeysResetRequested>((_, emit) => _run(emit, encryptionRepository.resetKeys, done: 'New keys made. Ask your partner to approve them.'));
  }

  final IEncryptionRepository encryptionRepository;

  SecurityReady? get _ready => state is SecurityReady ? state as SecurityReady : null;

  Future<void> _refresh(Emitter<SecurityState> emit, {bool quiet = false}) async {
    final before = _ready;
    if (before == null) emit(const SecurityLoading());
    final fresh = await encryptionRepository.sync();
    // Keep what we last knew when the check could not finish (no connection).
    final shown = fresh.phase == EncryptionPhase.unknown && before != null ? before.encryption : fresh;
    emit(SecurityReady(
      encryption:   shown,
      phraseToShow: before?.phraseToShow,
      notice:       !quiet && fresh.phase == EncryptionPhase.unknown ? 'Could not reach the server. Check your connection.' : null,
    ));
  }

  Future<void> _run(Emitter<SecurityState> emit, Future<EncryptionState> Function() action, {required String done, bool clearPhrase = false}) async {
    final before = _ready;
    if (before == null || before.busy) return;
    emit(before.copyWith(busy: true));
    try {
      final next = await action();
      final failed = next.phase == EncryptionPhase.unknown;
      emit(SecurityReady(
        encryption:   failed ? before.encryption : next,
        phraseToShow: clearPhrase && !failed ? null : before.phraseToShow,
        notice:       failed ? 'That did not finish. Check your connection and try again.' : done,
      ));
    } on CryptoException catch (err) {
      // For example "the code changed while you were looking": say so, and refresh what is on screen.
      emit(before.copyWith(busy: false, notice: err.message));
      add(const SecurityRefreshed());
    } catch (_) {
      emit(before.copyWith(busy: false, notice: 'Something went wrong. Try again.'));
    }
  }

  void _onPhraseRequested(RecoveryPhraseRequested _, Emitter<SecurityState> emit) {
    final ready = _ready;
    if (ready == null || ready.busy) return;
    emit(ready.copyWith(phraseToShow: encryptionRepository.newRecoveryPhrase()));
  }

  Future<void> _onRestore(RestoreSubmitted e, Emitter<SecurityState> emit) async {
    final before = _ready;
    if (before == null || before.busy) return;
    emit(before.copyWith(busy: true));
    try {
      emit(SecurityReady(encryption: await encryptionRepository.restoreWithPhrase(e.phrase), notice: 'Your keys are back on this phone'));
    } on CryptoException catch (err) {
      emit(before.copyWith(busy: false, notice: err.message));
    } catch (_) {
      emit(before.copyWith(busy: false, notice: 'Something went wrong. Try again.'));
    }
  }
}
