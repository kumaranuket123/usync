part of 'question_bloc.dart';

sealed class QuestionEvent { const QuestionEvent(); }
final class QuestionOpened extends QuestionEvent {
  QuestionOpened({required this.coupleId, required this.userId});
  final String coupleId, userId;
}
/// Re-checks whether the partner has answered (pull to refresh or a timer).
final class QuestionRefreshed extends QuestionEvent {}
final class QuestionAnswered extends QuestionEvent {
  QuestionAnswered(this.text);
  final String text;
}
