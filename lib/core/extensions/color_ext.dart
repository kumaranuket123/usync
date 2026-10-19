import 'package:flutter/material.dart';

extension ColorExt on Color {
  /// Returns a [BoxShadow] glow with this colour.
  BoxShadow glow({double blur = 20, double opacity = 0.5}) =>
      BoxShadow(color: withValues(alpha: opacity), blurRadius: blur);

  /// Returns a simple two-stop radial gradient centred on this colour.
  RadialGradient toRadialGlow({double opacity = 0.25}) => RadialGradient(
        colors: [withValues(alpha: opacity), withValues(alpha: 0)],
      );

  /// Converts this colour to a [LinearGradient] towards [other].
  LinearGradient toGradient(Color other, {AlignmentGeometry begin = Alignment.topLeft, AlignmentGeometry end = Alignment.bottomRight}) =>
      LinearGradient(colors: [this, other], begin: begin, end: end);
}
