import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

abstract final class HapticUtil {
  /// Light tap — selection, toggle, nav.
  static Future<void> light() => HapticFeedback.lightImpact();

  /// Medium tap — button press, action confirm.
  static Future<void> medium() => HapticFeedback.mediumImpact();

  /// Heavy tap — own touch press, important action.
  static Future<void> heavy() => HapticFeedback.heavyImpact();

  /// "Touch landing" — warm partner-touch arrival sequence.
  static Future<void> touchLanding() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 80, 60, 60, 60, 40]);
    } else {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 80));
      await HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 80));
      await HapticFeedback.lightImpact();
    }
  }

  /// Repeating pulse while partner is holding (call every ~1.2 s).
  static Future<void> touchPulse() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 100, 50, 100]);
    } else {
      await HapticFeedback.mediumImpact();
    }
  }
}
