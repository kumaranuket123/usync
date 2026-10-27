part of 'question_bloc.dart';

sealed class QuestionBlocState { const QuestionBlocState(); }
final class QuestionLoading extends QuestionBlocState {}
final class QuestionReady extends QuestionBlocState {
  const QuestionReady({required this.question, required this.answers, this.isSending = false, this.error});
  final DailyQuestion question;
  final QuestionState answers;
  final bool          isSending;
  final String?       error;
}
final class QuestionLoadFailed extends QuestionBlocState {
  const QuestionLoadFailed(this.message);
  final String message;
}
