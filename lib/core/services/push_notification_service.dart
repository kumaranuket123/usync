import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../data/datasources/local/prefs_source.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../constants/route_names.dart';
import '../di/injection.dart';
import '../router/app_router.dart';
import 'location_sync_service.dart';

/// Used by the app shell to show pushes that arrive while the app is open.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Runs in its own isolate when a data-only push arrives with the app in the
/// background or killed. Notification messages are shown by the OS; the only
/// data-only message is the partner's "locate" request.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.data['action'] == 'locate') await LocationSyncService.answerLocateRequest();
}

abstract final class PushNotificationService {
  static Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false, badge: true, sound: false,
    );

    await saveToken();
    messaging.onTokenRefresh.listen((_) => saveToken());

    // Foreground: show an in-app banner (the OS does not draw one).
    FirebaseMessaging.onMessage.listen(_showBanner);
    // Background -> tap.
    FirebaseMessaging.onMessageOpenedApp.listen(_openTarget);
    // Terminated -> tap.
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openTarget(initial));
    }
  }

  static Future<void> saveToken() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await getIt<IAuthRepository>().updateFcmToken(uid, token);
    } catch (_) {}
  }

  static void _showBanner(RemoteMessage message) {
    // The user switched push notifications off: no banners either.
    if (!getIt<PrefsSource>().notificationsEnabled) return;
    if (message.data['action'] == 'locate') {
      LocationSyncService.answerLocateRequest();
      return;
    }
    final n = message.notification;
    if (n == null) return;
    rootMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text([n.title, n.body].whereType<String>().join(' — ')),
        action: SnackBarAction(label: 'View', onPressed: () => _openTarget(message)),
      ));
  }

  static void _openTarget(RemoteMessage message) {
    if (Supabase.instance.client.auth.currentUser == null) return;
    final route = message.data['route'] as String?;
    AppRouter.router.go(route == RouteNames.notifications ? route! : RouteNames.notifications);
  }
}
