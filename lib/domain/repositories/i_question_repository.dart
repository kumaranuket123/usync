import '../entities/daily_question.dart';

abstract interface class IQuestionRepository {
  /// Today's answers for the couple. The partner's answer is only included
  /// once the caller has answered (enforced by the server).
  Future<QuestionState> getState(String coupleId, DailyQuestion question);

  /// Saves the caller's answer (final once sent) and tells the partner.
  Future<void> answer(String coupleId, String userId, DailyQuestion question, String text);
}
