import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/daily_question.dart';
import 'package:usync/domain/repositories/i_question_repository.dart';
import 'package:usync/presentation/features/question/bloc/question_bloc.dart';

class _FakeQuestionRepository implements IQuestionRepository {
  QuestionState state = const QuestionState();
  bool loadFails = false;
  Object? answerError;
  final answers = <String>[];

  @override
  Future<QuestionState> getState(String coupleId, DailyQuestion question) async {
    if (loadFails) throw Exception('offline');
    return state;
  }

  @override
  Future<void> answer(String coupleId, String userId, DailyQuestion question, String text) async {
    if (answerError != null) throw answerError!;
    answers.add(text);
    state = QuestionState(myAnswer: text, partnerAnswered: state.partnerAnswered, partnerAnswer: state.partnerAnswer == null && state.partnerAnswered ? 'theirs' : state.partnerAnswer);
  }
}

void main() {
  group('DailyQuestion.forDay', () {
    test('is the same for both partners on the same UTC day', () {
      final a = DailyQuestion.forDay(DateTime.utc(2026, 3, 5, 0, 1));
      final b = DailyQuestion.forDay(DateTime.utc(2026, 3, 5, 23, 59));
      expect(a, b);
      expect(a.day, '2026-03-05');
    });

    test('changes the next day', () {
      final a = DailyQuestion.forDay(DateTime.utc(2026, 3, 5));
      final b = DailyQuestion.forDay(DateTime.utc(2026, 3, 6));
      expect(a.index, isNot(b.index));
    });
  });

  group('QuestionBloc', () {
    late _FakeQuestionRepository repo;
    late QuestionBloc bloc;

    setUp(() {
      repo = _FakeQuestionRepository();
      bloc = QuestionBloc(questionRepository: repo, clock: () => DateTime.utc(2026, 3, 5));
    });
    tearDown(() => bloc.close());

    Future<void> open() async {
      bloc.add(QuestionOpened(coupleId: 'c', userId: 'u'));
      await bloc.stream.firstWhere((s) => s is! QuestionLoading);
    }

    test('loads today\'s question', () async {
      await open();
      final s = bloc.state as QuestionReady;
      expect(s.question.day, '2026-03-05');
      expect(s.answers.iAnswered, isFalse);
    });

    test('reports a failed load', () async {
      repo.loadFails = true;
      await open();
      expect(bloc.state, isA<QuestionLoadFailed>());
    });

    test('an empty answer is rejected without calling the repository', () async {
      await open();
      bloc.add(QuestionAnswered('   '));
      await bloc.stream.firstWhere((s) => s is QuestionReady && s.error != null);
      expect(repo.answers, isEmpty);
    });

    test('answering reveals the partner\'s answer when they have replied', () async {
      repo.state = const QuestionState(partnerAnswered: true);
      await open();
      bloc.add(QuestionAnswered('  me too  '));
      await bloc.stream.firstWhere((s) => s is QuestionReady && s.answers.iAnswered);
      final s = bloc.state as QuestionReady;
      expect(repo.answers, ['me too']);
      expect(s.answers.revealed, isTrue);
    });

    test('a failed send keeps the form and shows an error', () async {
      repo.answerError = Exception('boom');
      await open();
      bloc.add(QuestionAnswered('hi'));
      await bloc.stream.firstWhere((s) => s is QuestionReady && s.error != null);
      expect((bloc.state as QuestionReady).answers.iAnswered, isFalse);
    });
  });
}
