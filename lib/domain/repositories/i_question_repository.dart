import '../entities/daily_question.dart';

abstract interface class IQuestionRepository {
  /// Today's answers for the couple, already decrypted. The partner's answer is only included once
  /// the caller has answered (enforced by the server). [userId] and [partnerId] say whose answer is
  /// whose: each answer is bound to its author when it is encrypted.
  Future<QuestionState> getState(String coupleId, DailyQuestion question, {required String userId, required String partnerId});

  /// Encrypts and saves the caller's answer (final once sent) and tells the partner. Throws
  /// `EncryptionNotReady`, saving nothing, if this phone does not have the couple key yet.
  Future<void> answer(String coupleId, String userId, DailyQuestion question, String text);
}
