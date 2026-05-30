import 'package:flutter/material.dart';

extension ColorExt on Color {
  /// Returns a [BoxShadow] glow with this colour.
  BoxShadow glow({double blur = 20, double opacity = 0.5}) =>
      BoxShadow(color: withOpacity(opacity), blurRadius: blur);

  /// Returns a simple two-stop radial gradient centred on this colour.
  RadialGradient toRadialGlow({double opacity = 0.25}) => RadialGradient(
        colors: [withOpacity(opacity), withOpacity(0)],
      );

  /// Converts this colour to a [LinearGradient] towards [other].
  LinearGradient toGradient(Color other, {AlignmentGeometry begin = Alignment.topLeft, AlignmentGeometry end = Alignment.bottomRight}) =>
      LinearGradient(colors: [this, other], begin: begin, end: end);
}
