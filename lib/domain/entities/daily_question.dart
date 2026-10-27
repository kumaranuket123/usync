import 'package:equatable/equatable.dart';

import 'couple.dart';

/// The question both partners see on a given (UTC) day. The text lives in the
/// app; only the answer and the question's index are stored.
class DailyQuestion extends Equatable {
  const DailyQuestion({required this.index, required this.text, required this.day});

  final int      index;
  final String   text;
  /// UTC calendar day, as 'yyyy-MM-dd'. Matches the server's streak day.
  final String   day;

  static const commonBank = <String>[
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

  /// Extra questions for couples who live apart.
  static const longDistanceBank = <String>[
    'What is one small ritual that makes the distance feel shorter?',
    'What do you miss most about being in the same room as me?',
    'What is the first thing we should do the moment we are together again?',
    'When do you feel closest to me even though we are apart?',
    'What is something you wish I could see from your day?',
    'What helps you most when you miss me?',
    'Where would you like us to meet next?',
    'What is the best thing about how we stay connected?',
    'What is something you want us to do together online this week?',
    'What would make our time apart easier for you?',
  ];

  /// Extra questions for couples who live together.
  static const togetherBank = <String>[
    'What is your favourite thing we do around the house?',
    'What is a small chore you secretly enjoy doing with me?',
    'What would make our evenings together even better?',
    'What is one thing you would like us to cook together?',
    'What is your favourite way we spend a quiet morning?',
    'What is a place nearby you want us to explore together?',
    'What is something I do at home that makes you feel loved?',
    'What habit of ours would you like to keep forever?',
    'What would your perfect weekend with me look like?',
    'What is one thing you would like to change about our routine?',
  ];

  /// The questions for a couple: the shared ones plus their mode's own.
  static List<String> bankFor(RelationshipMode mode) => [
    ...commonBank,
    ...(mode == RelationshipMode.longDistance ? longDistanceBank : togetherBank),
  ];

  /// Same question for both partners: it depends only on the UTC day and the
  /// couple's (shared) relationship mode.
  factory DailyQuestion.forDay(DateTime now, {RelationshipMode mode = RelationshipMode.together}) {
    final utc  = now.toUtc();
    final day  = DateTime.utc(utc.year, utc.month, utc.day);
    final bank = bankFor(mode);
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
