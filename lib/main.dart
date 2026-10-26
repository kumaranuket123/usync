import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/constants/supabase_config.dart';
import 'core/di/injection.dart';
import 'core/services/app_lock_service.dart';
import 'core/utils/api_call_logger.dart';
import 'core/services/outbox_service.dart';
import 'domain/repositories/i_canvas_repository.dart';
import 'domain/repositories/i_memory_repository.dart';
import 'domain/repositories/i_milestone_repository.dart';
import 'domain/repositories/i_mood_repository.dart';
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

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
  ));

  runApp(const UsyncApp());
}
