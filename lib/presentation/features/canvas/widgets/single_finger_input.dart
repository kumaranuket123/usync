import 'package:flutter/widgets.dart';

/// Turns touches into one stroke at a time. The first finger down draws; a second finger or a resting
/// palm is ignored until it lifts, because a pan gesture would jump to it and draw a straight line between
/// the two. Reading raw pointers also removes the delay before a pan starts, so a stroke is not cut short.
class SingleFingerInput extends StatefulWidget {
  const SingleFingerInput({
    super.key,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  final ValueChanged<Offset> onStart, onUpdate;
  final VoidCallback         onEnd;
  final Widget               child;

  @override
  State<SingleFingerInput> createState() => _SingleFingerInputState();
}

class _SingleFingerInputState extends State<SingleFingerInput> {
  int? _pointer;

  void _end(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null) return;
          _pointer = e.pointer;
          widget.onStart(e.localPosition);
        },
        onPointerMove: (e) {
          if (e.pointer == _pointer) widget.onUpdate(e.localPosition);
        },
        onPointerUp: _end,
        onPointerCancel: _end,
        child: widget.child,
      );
}
