import '../entities/game_answer.dart';

/// One partner's row for a round of the quiz: their own pick and their guess of the partner's pick.
class QuizEntry {
  const QuizEntry({required this.self, required this.guess});
  final int self, guess;

  static QuizEntry? fromAnswer(GameAnswer? a) {
    final self = a?.content?['self'], guess = a?.content?['guess'];
    return self is int && guess is int ? QuizEntry(self: self, guess: guess) : null;
  }
}

/// Scoring of the quiz, with no I/O so it can be tested on its own.
class QuizScoring {
  const QuizScoring._();

  /// Rounds where [guesser] named the partner's real pick. Only rounds both have answered count.
  static int correctGuesses({required Map<int, QuizEntry> guesser, required Map<int, QuizEntry> partner}) =>
      guesser.entries.where((e) => partner[e.key]?.self == e.value.guess).length;
}
