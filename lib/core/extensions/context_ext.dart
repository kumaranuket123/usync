import 'package:flutter/material.dart';

import '../theme/usync_theme_data.dart';

extension ContextExt on BuildContext {
  /// Access custom Usync theme tokens.
  UsyncThemeData get usync => Theme.of(this).extension<UsyncThemeData>()!;

  /// Access Material ColorScheme.
  ColorScheme get colors => Theme.of(this).colorScheme;

  /// Screen size shortcuts.
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth  => screenSize.width;
  double get screenHeight => screenSize.height;

  /// Safe area padding.
  EdgeInsets get padding => MediaQuery.paddingOf(this);
  double get topPadding    => padding.top;
  double get bottomPadding => padding.bottom;

  /// Navigation helpers.
  void pop<T>([T? result]) => Navigator.of(this).pop(result);
  bool get canPop => Navigator.of(this).canPop();
}
