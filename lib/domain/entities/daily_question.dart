import 'package:equatable/equatable.dart';

/// The question both partners see on a given (UTC) day. The text lives in the
/// app; only the answer and the question's index are stored.
class DailyQuestion extends Equatable {
  const DailyQuestion({required this.index, required this.text, required this.day});

  final int      index;
  final String   text;
  /// UTC calendar day, as 'yyyy-MM-dd'. Matches the server's streak day.
  final String   day;

  static const bank = <String>[
    'What is a small thing I do that makes your day better?',
    'What is your favourite memory of us so far?',
    'What is something you want us to try together this year?',
    'When did you last feel really close to me?',
    'What song reminds you of us, and why?',
    'What is one thing you are proud of me for?',
    'What would your perfect lazy day with me look like?',
    'What is something you have never told me you love about us?',
    'What is a dream you have that you have not shared yet?',
    'What made you smile today?',
    'What is one thing I could do to support you this week?',
    'Which moment made you realise you cared about me?',
    'What is a tradition you would like us to start?',
    'What is your favourite thing about how we talk?',
    'If we could be anywhere together right now, where would it be?',
    'What is something small I did that you still remember?',
    'What do you need more of from us lately?',
    'What is your favourite photo of us?',
    'What is one fear you would like me to know about?',
    'What are you looking forward to the most with me?',
  ];

  /// Same question for both partners: it depends only on the UTC day.
  factory DailyQuestion.forDay(DateTime now) {
    final utc  = now.toUtc();
    final day  = DateTime.utc(utc.year, utc.month, utc.day);
    final idx  = day.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay % bank.length;
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return DailyQuestion(index: idx, text: bank[idx], day: '$y-$m-$d');
  }

  @override
  List<Object?> get props => [index, day];
}

/// Today's answers. The partner's text is null until you have answered too.
class QuestionState extends Equatable {
  const QuestionState({this.myAnswer, this.partnerAnswered = false, this.partnerAnswer});

  final String? myAnswer;
  final bool    partnerAnswered;
  final String? partnerAnswer;

  bool get iAnswered => myAnswer != null;
  bool get revealed  => iAnswered && partnerAnswer != null;

  @override
  List<Object?> get props => [myAnswer, partnerAnswered, partnerAnswer];
}
