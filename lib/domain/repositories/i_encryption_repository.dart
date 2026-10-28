import '../entities/encryption_state.dart';

abstract interface class IEncryptionRepository {
  /// The last state worked out on this phone (instant, no network).
  EncryptionState get current;

  /// Brings this phone's keys in line with the server: creates and publishes our key the first
  /// time, shares the couple's key, notices a partner whose keys changed. Safe to call as often
  /// as you like. Never throws: if it cannot finish it returns [EncryptionPhase.unknown].
  Future<EncryptionState> sync();

  /// The person compared [securityCode] with their partner and it matched. Only that exact code is
  /// confirmed: if the code the server serves now differs (it changed while they were looking), this
  /// throws a `CryptoException` and confirms nothing.
  Future<EncryptionState> markPartnerVerified(String securityCode);

  /// A new 12-word recovery phrase. It is not saved anywhere until [finishRecovery].
  String newRecoveryPhrase();

  /// Seals this account's identity key with [phrase] and stores the backup on the server.
  Future<EncryptionState> finishRecovery(String phrase);

  /// New phone: puts the identity key back using the recovery [phrase]. Throws a
  /// `CryptoException` for a wrong phrase.
  Future<EncryptionState> restoreWithPhrase(String phrase);

  /// Lost phrase: throws the old keys away and makes new ones, which the partner must approve.
  Future<EncryptionState> resetKeys();

  /// The partner's keys changed and the person compared [securityCode] with them: share the couple's
  /// key with the new keys. Throws a `CryptoException`, changing nothing, if the code the server
  /// serves now is not the one that was compared.
  Future<EncryptionState> approvePartnerKey(String securityCode);
}
