import 'package:flutter/material.dart';

/// The app's snackbar. Use this instead of `SnackBar(...)` so every message
/// behaves the same:
/// - It always goes away by itself after [duration]. Flutter keeps a snackbar
///   that has an action (Retry, View) on screen until it is dismissed, which
///   is not what we want for passing messages.
/// - It can be swiped away left or right (Flutter's built-in dismissal), and
///   down as well (added here, since a snackbar takes only one direction).
SnackBar appSnackBar({
  required Widget content,
  SnackBarAction? action,
  SnackBarBehavior? behavior,
  Duration duration = const Duration(seconds: 4),
}) =>
    SnackBar(
      content: _SwipeDownToDismiss(child: content),
      action: action,
      behavior: behavior,
      duration: duration,
      persist: false,
      dismissDirection: DismissDirection.horizontal,
    );

class _SwipeDownToDismiss extends StatelessWidget {
  const _SwipeDownToDismiss({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 100) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar(reason: SnackBarClosedReason.swipe);
        }
      },
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}
