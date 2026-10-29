import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/games/tic_tac_toe.dart';

void main() {
  test('X starts and marks alternate', () {
    var b = TicTacToe.empty;
    expect(TicTacToe.nextMark(b), 'X');
    b = TicTacToe.play(b, 4);
    expect(b[4], 'X');
    expect(TicTacToe.nextMark(b), 'O');
    b = TicTacToe.play(b, 0);
    expect(b[0], 'O');
  });

  test('a taken cell or one off the board cannot be played', () {
    final b = TicTacToe.play(TicTacToe.empty, 0);
    expect(TicTacToe.canPlay(b, 0), isFalse);
    expect(TicTacToe.canPlay(b, 9), isFalse);
    expect(TicTacToe.canPlay(b, -1), isFalse);
    expect(() => TicTacToe.play(b, 0), throwsArgumentError);
  });

  test('detects a win in a row, column and diagonal', () {
    expect(TicTacToe.outcome('XXXOO    '), 'X'); // row
    expect(TicTacToe.outcome('O  O  O X'), 'O'); // column
    expect(TicTacToe.outcome('XO OX   X'), 'X'); // diagonal
    expect(TicTacToe.outcome('X   X    '), isNull); // two in a line is not a win
  });

  test('a full board with no line is a draw', () {
    expect(TicTacToe.outcome('XOXXOOOXX'), 'draw');
  });

  test('no move after the game is won', () {
    expect(TicTacToe.canPlay('XXXOO    ', 5), isFalse);
  });

  test('an unfinished board has no outcome', () {
    expect(TicTacToe.outcome(TicTacToe.empty), isNull);
  });
}
