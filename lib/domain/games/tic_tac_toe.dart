/// Rules of tic-tac-toe, with no I/O so they can be tested on their own.
///
/// The board is nine characters, row by row: `X`, `O` or a space for an empty cell.
class TicTacToe {
  const TicTacToe._();

  static const empty = '         ';

  static const _lines = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
    [0, 3, 6], [1, 4, 7], [2, 5, 8], // columns
    [0, 4, 8], [2, 4, 6],            // diagonals
  ];

  /// `X` or `O` when a line is complete, `draw` when the board is full, otherwise null.
  static String? outcome(String board) {
    for (final l in _lines) {
      final c = board[l[0]];
      if (c != ' ' && c == board[l[1]] && c == board[l[2]]) return c;
    }
    return board.contains(' ') ? null : 'draw';
  }

  /// Whose mark goes next: X always starts, so equal counts mean X.
  static String nextMark(String board) {
    final x = 'X'.allMatches(board).length;
    final o = 'O'.allMatches(board).length;
    return x <= o ? 'X' : 'O';
  }

  static bool canPlay(String board, int cell) =>
      board.length == 9 && cell >= 0 && cell < 9 && board[cell] == ' ' && outcome(board) == null;

  /// The board after the next mark is placed on [cell]. Throws if the move is not allowed.
  static String play(String board, int cell) {
    if (!canPlay(board, cell)) throw ArgumentError('Cell $cell is not playable');
    return board.replaceRange(cell, cell + 1, nextMark(board));
  }
}
