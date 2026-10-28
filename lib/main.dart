import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/constants/supabase_config.dart';
import 'core/di/injection.dart';
import 'core/services/app_lock_service.dart';
import 'data/datasources/local/local_memory_images.dart';
import 'core/utils/api_call_logger.dart';
import 'core/services/outbox_service.dart';
import 'domain/repositories/i_canvas_repository.dart';
import 'domain/repositories/i_memory_repository.dart';
import 'domain/repositories/i_milestone_repository.dart';
import 'domain/repositories/i_mood_repository.dart';
import 'core/services/home_widget_service.dart';
import 'core/services/reminder_service.dart';
import 'core/services/location_sync_service.dart';
import 'core/services/push_notification_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Supabase.initialize(
    url:            SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    // Debug builds count every request (see ApiCallLogger); release builds are unchanged.
    httpClient:     kDebugMode ? ApiCallLogger() : null,
  );

  await Hive.initFlutter();
  await setupLocator();
  getIt<AppLockService>().init();

  // Repositories that send queued changes must exist before the outbox starts
  // flushing, because each registers its handler when it is created.
  getIt<IMoodRepository>();
  getIt<IMemoryRepository>();
  getIt<ICanvasRepository>();
  getIt<IMilestoneRepository>();
  await getIt<OutboxService>().init();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await PushNotificationService.init();
  LocationSyncService.init();
  HomeWidgetService.init();
  ReminderSync.init(getIt<ReminderService>());
  // Pictures kept on the phone by earlier versions were readable files: seal them (cheap when there are none).
  unawaited(LocalMemoryImages.sealLegacy().catchError((Object _) {}));
  // Earlier versions kept readable copies of memory pictures in the image cache: empty it once.
  unawaited(_clearLegacyImageCache());

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
  ));

  runApp(const UsyncApp());
}

/// Pictures are now downloaded and opened in memory, never cached as readable files.
Future<void> _clearLegacyImageCache() async {
  try {
    final prefs = getIt<SharedPreferences>();
    if (prefs.getBool('legacy_image_cache_cleared') == true) return;
    await DefaultCacheManager().emptyCache();
    await prefs.setBool('legacy_image_cache_cleared', true);
  } catch (_) {
    // Tried again next start.
  }
}
