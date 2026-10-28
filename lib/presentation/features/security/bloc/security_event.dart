part of 'security_bloc.dart';

sealed class SecurityEvent { const SecurityEvent(); }
final class SecurityOpened extends SecurityEvent { const SecurityOpened(); }
final class SecurityRefreshed extends SecurityEvent { const SecurityRefreshed(); }
/// [securityCode] is the code the person was looking at when they said it matches.
final class PartnerVerifiedMarked extends SecurityEvent {
  const PartnerVerifiedMarked(this.securityCode);
  final String securityCode;
}
final class PartnerKeyApproved extends SecurityEvent {
  const PartnerKeyApproved(this.securityCode);
  final String securityCode;
}
/// Asks for a new recovery phrase to show.
final class RecoveryPhraseRequested extends SecurityEvent { const RecoveryPhraseRequested(); }
/// The sheet was closed without confirming: forget the pending phrase.
final class RecoveryPhraseDismissed extends SecurityEvent { const RecoveryPhraseDismissed(); }
/// The person saved the phrase and passed the quiz: store the backup.
final class RecoveryPhraseConfirmed extends SecurityEvent {
  const RecoveryPhraseConfirmed(this.phrase);
  final String phrase;
}
final class RestoreSubmitted extends SecurityEvent {
  const RestoreSubmitted(this.phrase);
  final String phrase;
}
final class KeysResetRequested extends SecurityEvent { const KeysResetRequested(); }
