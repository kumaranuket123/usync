import 'package:flutter/services.dart';

/// Blocks screenshots, screen recording and the app-switcher preview while the private chat is
/// open (Android `FLAG_SECURE`, see MainActivity). iOS cannot block them, so this does nothing there.
abstract final class SecureScreen {
  static const _channel = MethodChannel('usync/secure_screen');

  static Future<void> set(bool on) async {
    try {
      await _channel.invokeMethod<void>('set', on);
    } on MissingPluginException {
      // Not Android (or a test): nothing to block.
    } on PlatformException {
      // Best effort.
    }
  }
}
