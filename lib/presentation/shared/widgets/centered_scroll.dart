import 'package:flutter/material.dart';

/// Centres [child] like [Center] does, but scrolls when the content is taller
/// than the space (a small phone, a large font size or the keyboard) instead of
/// overflowing.
class CenteredScroll extends StatelessWidget {
  const CenteredScroll({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}
