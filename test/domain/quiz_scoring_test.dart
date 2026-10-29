import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/game_answer.dart';
import 'package:usync/domain/games/quiz_scoring.dart';

void main() {
  const me      = {0: QuizEntry(self: 1, guess: 2), 1: QuizEntry(self: 0, guess: 3), 2: QuizEntry(self: 2, guess: 0)};
  const partner = {0: QuizEntry(self: 2, guess: 1), 1: QuizEntry(self: 1, guess: 1)};

  test('counts the partner answers a player guessed', () {
    expect(QuizScoring.correctGuesses(guesser: me, partner: partner), 1); // round 0 only
  });

  test("counts the other way round, and skips rounds the partner has not answered", () {
    expect(QuizScoring.correctGuesses(guesser: partner, partner: me), 1); // round 0: partner guessed my 1
  });

  test('no shared rounds means no points', () {
    expect(QuizScoring.correctGuesses(guesser: me, partner: const {}), 0);
  });

  test('reads an entry from an answer, and ignores one without both numbers', () {
    expect(QuizEntry.fromAnswer(const GameAnswer(round: 0, userId: 'u', content: {'self': 1, 'guess': 2}))!.guess, 2);
    expect(QuizEntry.fromAnswer(const GameAnswer(round: 0, userId: 'u', content: {'pick': 'A'})), isNull);
    expect(QuizEntry.fromAnswer(const GameAnswer(round: 0, userId: 'u', content: null)), isNull);
    expect(QuizEntry.fromAnswer(null), isNull);
  });
}
