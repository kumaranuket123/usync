import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/couple.dart';
import '../../../../domain/entities/daily_question.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_question_repository.dart';

part 'question_event.dart';
part 'question_state.dart';

class QuestionBloc extends Bloc<QuestionEvent, QuestionBlocState> {
  QuestionBloc({required this.questionRepository, required this.coupleRepository, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        super(QuestionLoading()) {
    on<QuestionOpened>(_onOpened);
    on<QuestionRefreshed>(_onRefreshed);
    on<QuestionAnswered>(_onAnswered);
  }

  final IQuestionRepository questionRepository;
  final ICoupleRepository   coupleRepository;
  final DateTime Function()  _clock;
  String _coupleId = '';
  String _userId   = '';

  Future<void> _onOpened(QuestionOpened e, Emitter<QuestionBlocState> emit) async {
    _coupleId = e.coupleId;
    _userId   = e.userId;
    emit(QuestionLoading());
    // Both partners must see the same question, so the couple's shared mode picks the bank.
    var mode = RelationshipMode.together;
    try {
      mode = await coupleRepository.getRelationshipMode(_coupleId);
    } catch (_) {
      // Unreadable (offline, nothing saved): the default bank still works.
    }
    final question = DailyQuestion.forDay(_clock(), mode: mode);
    try {
      emit(QuestionReady(
        question: question,
        answers:  await questionRepository.getState(_coupleId, question),
      ));
    } catch (_) {
      emit(const QuestionLoadFailed('Could not load today\'s question. Check your connection.'));
    }
  }

  Future<void> _onRefreshed(QuestionRefreshed _, Emitter<QuestionBlocState> emit) async {
    final current = state;
    if (current is! QuestionReady || current.isSending) return;
    try {
      final answers = await questionRepository.getState(_coupleId, current.question);
      if (answers != current.answers) emit(QuestionReady(question: current.question, answers: answers));
    } catch (_) {
      // Keep what is on screen; the next refresh tries again.
    }
  }

  Future<void> _onAnswered(QuestionAnswered e, Emitter<QuestionBlocState> emit) async {
    final current = state;
    if (current is! QuestionReady || current.isSending || current.answers.iAnswered) return;
    final text = e.text.trim();
    if (text.isEmpty) {
      emit(QuestionReady(question: current.question, answers: current.answers, error: 'Write an answer first'));
      return;
    }
    emit(QuestionReady(question: current.question, answers: current.answers, isSending: true));
    try {
      await questionRepository.answer(_coupleId, _userId, current.question, text);
      emit(QuestionReady(
        question: current.question,
        answers:  await questionRepository.getState(_coupleId, current.question),
      ));
    } catch (_) {
      emit(QuestionReady(
        question: current.question,
        answers:  current.answers,
        error:    'Could not send your answer. Try again.',
      ));
    }
  }
}
