import 'package:equatable/equatable.dart';

/// Where this phone stands with end-to-end encryption.
enum EncryptionPhase {
  /// Not checked yet, or the check could not finish (no connection). Nothing is lost.
  unknown,
  /// This account already has keys, but not on this phone (new phone or reinstall): restore them.
  needsRestore,
  /// Our keys are in place and there is no partner yet.
  noCouple,
  /// The partner has not set up their keys yet (they need to open the app).
  waitingForPartner,
  /// Both phones have keys, but nobody has compared the security code yet. Nothing is shared
  /// until a person has confirmed the code, so a swapped key cannot get the couple's key.
  needsVerification,
  /// The couple's key has not been shared with this phone yet; the partner's phone does that.
  waitingForKey,
  /// This phone's keys changed; the partner must approve the new keys before it can read.
  needsApproval,
  /// The partner's keys changed; compare the security code, then approve them.
  partnerKeyChanged,
  /// The code was compared, the couple's key is here and trusted: everything can be encrypted and read.
  ready,
}

class EncryptionState extends Equatable {
  const EncryptionState({
    this.phase = EncryptionPhase.unknown,
    this.securityCode,
    this.partnerVerified = false,
    this.recoverySetUp = false,
    this.coupleId,
  });

  const EncryptionState.unknown() : this();

  final EncryptionPhase phase;
  /// Sixty digits both partners compare; null until both public keys are known.
  final String?         securityCode;
  /// The current security code (both keys) was compared and confirmed on this phone.
  final bool            partnerVerified;
  /// A recovery phrase was saved for this account.
  final bool            recoverySetUp;
  final String?         coupleId;

  bool get isReady => phase == EncryptionPhase.ready;

  EncryptionState copyWith({EncryptionPhase? phase, bool? recoverySetUp, bool? partnerVerified}) => EncryptionState(
        phase:           phase           ?? this.phase,
        securityCode:    securityCode,
        partnerVerified: partnerVerified ?? this.partnerVerified,
        recoverySetUp:   recoverySetUp   ?? this.recoverySetUp,
        coupleId:        coupleId,
      );

  @override
  List<Object?> get props => [phase, securityCode, partnerVerified, recoverySetUp, coupleId];
}
