import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/content_cipher.dart';
import '../crypto/crypto_service.dart';
import '../../data/datasources/remote/encryption_backend.dart';
import '../../data/repositories/encryption_context.dart';
import '../../data/repositories/encryption_repository.dart';
import '../../domain/repositories/i_encryption_repository.dart';
import '../../presentation/features/security/bloc/security_bloc.dart';
import '../crypto/key_service.dart';
import '../crypto/secure_key_store.dart';
import '../../data/datasources/local/hive_source.dart';
import '../../data/datasources/local/prefs_source.dart';
import '../../data/datasources/remote/couple_channel_source.dart';
import '../../data/datasources/remote/storage_source.dart';
import '../../data/datasources/remote/supabase_auth_source.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/canvas_repository.dart';
import '../../data/repositories/couple_repository.dart';
import '../../data/repositories/memory_repository.dart';
import '../../data/repositories/mood_repository.dart';
import '../../data/datasources/local/flutter_secure_key_store.dart';
import '../../data/repositories/access_repository.dart';
import '../../data/repositories/bucket_repository.dart';
import '../../data/repositories/question_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/datasources/local/identity_cache.dart';
import '../../data/datasources/local/session_cache.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/repositories/milestone_repository.dart';
import '../../domain/repositories/i_milestone_repository.dart';
import '../services/outbox_service.dart';
import '../services/app_lock_service.dart';
import '../../data/repositories/touch_repository.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../../domain/repositories/i_canvas_repository.dart';
import '../../domain/repositories/i_couple_repository.dart';
import '../../domain/repositories/i_memory_repository.dart';
import '../../domain/repositories/i_mood_repository.dart';
import '../../domain/repositories/i_access_repository.dart';
import '../../domain/repositories/i_bucket_repository.dart';
import '../../domain/repositories/i_question_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../../domain/repositories/i_location_repository.dart';
import '../../domain/repositories/i_touch_repository.dart';
import '../../presentation/features/auth/bloc/auth_bloc.dart';
import '../../presentation/features/canvas/bloc/canvas_bloc.dart';
import '../../presentation/features/home/bloc/home_bloc.dart';
import '../../presentation/features/memory/bloc/memory_bloc.dart';
import '../../presentation/features/mood/bloc/mood_bloc.dart';
import '../../presentation/features/mood_insights/bloc/mood_insights_bloc.dart';
import '../../presentation/features/long_distance/bloc/long_distance_bloc.dart';
import '../../presentation/features/bucket/bloc/bucket_bloc.dart';
import '../../presentation/features/question/bloc/question_bloc.dart';
import '../../presentation/features/notifications/bloc/notification_bloc.dart';
import '../../presentation/features/pairing/bloc/pairing_bloc.dart';
import '../../presentation/features/profile/bloc/profile_bloc.dart';
import '../../presentation/features/settings/bloc/settings_bloc.dart';
import '../../presentation/features/settings/bloc/theme_bloc.dart';
import '../../presentation/features/timeline/bloc/timeline_bloc.dart';
import '../../presentation/features/location/bloc/location_bloc.dart';
import '../../presentation/features/touch_sync/bloc/touch_sync_bloc.dart';
import '../../presentation/features/widgets_showcase/bloc/widgets_bloc.dart';

final GetIt getIt = GetIt.instance;

Future<void> setupLocator() async {
  // ── External ──────────────────────────────────────────────────
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);
  getIt.registerSingleton<SupabaseClient>(Supabase.instance.client);

  // ── Data sources ──────────────────────────────────────────────
  getIt.registerLazySingleton<SupabaseAuthSource>(
    () => SupabaseAuthSource(client: getIt()),
  );
  getIt.registerLazySingleton<StorageSource>(() => StorageSource(client: getIt()));
  getIt.registerLazySingleton<CoupleChannelSource>(
    () => CoupleChannelSource(client: getIt()),
  );
  getIt.registerLazySingleton<HiveSource>(() => HiveSource());
  getIt.registerLazySingleton<PrefsSource>(
    () => PrefsSource(prefs: getIt()),
  );

  // ── Encryption (not used by any feature yet) ──────────────────
  getIt.registerLazySingleton<SecureKeyStore>(() => const FlutterSecureKeyStore());
  getIt.registerLazySingleton<CryptoService>(() => CryptoService());
  getIt.registerLazySingleton<KeyServiceFor>(
    () => (userId) => KeyService(store: getIt(), crypto: getIt(), namespace: userId),
  );
  getIt.registerLazySingleton<ContentCipher>(
    () => ContentCipher(
      keysFor: getIt(),
      currentUserId: () => getIt<SupabaseClient>().auth.currentUser?.id,
      crypto: getIt(),
    ),
  );
  getIt.registerLazySingleton<EncryptionBackend>(() => SupabaseEncryptionBackend(client: getIt()));

  getIt.registerLazySingleton<AppLockService>(() => AppLockService(prefs: getIt()));

  // ── Offline support ───────────────────────────────────────────
  // Changes made without a connection wait in the outbox; the session cache
  // keeps who you are, your couple and recent data so the app can start offline.
  getIt.registerSingleton<SessionCache>(
    SessionCache(box: await Hive.openBox<dynamic>(SessionCache.boxName)),
  );
  getIt.registerSingleton<IdentityCache>(IdentityCache());
  getIt.registerSingleton<OutboxService>(
    OutboxService(box: await Hive.openBox<dynamic>('outbox')),
  );

  // ── Repositories ──────────────────────────────────────────────
  getIt.registerLazySingleton<IAuthRepository>(
    () => AuthRepository(
      authSource: getIt(),
      client: getIt(),
      prefsSource: getIt(),
      sessionCache: getIt(),
      outbox: getIt(),
      identity: getIt(),
      channels: getIt(),
      storage: getIt(),
      wipeKeys: (userId) => getIt<KeyServiceFor>()(userId).clearAll(),
    ),
  );
  getIt.registerLazySingleton<ICoupleRepository>(
    () => CoupleRepository(
      client: getIt(),
      channelSource: getIt(),
      notifications: getIt(),
      storage: getIt(),
      sessionCache: getIt(),
      identity: getIt(),
      cipher: getIt(),
    ),
  );
  getIt.registerLazySingleton<IMoodRepository>(
    () => MoodRepository(
      client: getIt(),
      notifications: getIt(),
      outbox: getIt(),
      sessionCache: getIt(),
      cipher: getIt(),
    ),
  );
  getIt.registerLazySingleton<IAccessRepository>(
    () => AccessRepository(client: getIt(), prefs: getIt()),
  );
  getIt.registerLazySingleton<IEncryptionRepository>(
    () => EncryptionRepository(
      backend: getIt(),
      context: AppEncryptionContext(authRepository: getIt(), coupleRepository: getIt()),
      keysFor: getIt(),
    ),
  );
  getIt.registerLazySingleton<IBucketRepository>(
    () => BucketRepository(
      client: getIt(),
      notifications: getIt(),
      outbox: getIt(),
      sessionCache: getIt(),
      cipher: getIt(),
    ),
  );
  getIt.registerLazySingleton<IQuestionRepository>(
    () => QuestionRepository(client: getIt(), notifications: getIt(), cipher: getIt()),
  );
  getIt.registerLazySingleton<IMilestoneRepository>(
    () => MilestoneRepository(
      client: getIt(),
      notifications: getIt(),
      outbox: getIt(),
      sessionCache: getIt(),
    ),
  );
  getIt.registerLazySingleton<IMemoryRepository>(
    () => MemoryRepository(client: getIt(), storage: getIt(), notifications: getIt(), outbox: getIt(), prefs: getIt(), cipher: getIt()),
  );
  getIt.registerLazySingleton<ICanvasRepository>(
    () => CanvasRepository(client: getIt(), channelSource: getIt(), outbox: getIt(), cipher: getIt()),
  );
  getIt.registerLazySingleton<ITouchRepository>(
    () => TouchRepository(channelSource: getIt(), notifications: getIt()),
  );
  getIt.registerLazySingleton<ILocationRepository>(
    () => LocationRepository(client: getIt(), prefs: getIt(), notifications: getIt(), cipher: getIt()),
  );
  getIt.registerLazySingleton<INotificationRepository>(
    () => NotificationRepository(client: getIt(), cipher: getIt()),
  );

  // ── BLoCs (factory — new instance per registration request) ───
  getIt.registerFactory<AuthBloc>(
    () => AuthBloc(authRepository: getIt()),
  );
  getIt.registerFactory<SettingsBloc>(
    () => SettingsBloc(prefsSource: getIt(), notifications: getIt()),
  );
  getIt.registerFactory<ThemeBloc>(
    () => ThemeBloc(prefsSource: getIt()),
  );
  getIt.registerFactory<PairingBloc>(
    () => PairingBloc(coupleRepository: getIt()),
  );
  getIt.registerFactory<HomeBloc>(
    () => HomeBloc(
      authRepository:   getIt(),
      coupleRepository: getIt(),
      moodRepository:   getIt(),
    ),
  );
  getIt.registerFactory<CanvasBloc>(
    () => CanvasBloc(canvasRepository: getIt(), memoryRepository: getIt()),
  );
  getIt.registerFactory<TouchSyncBloc>(
    () => TouchSyncBloc(touchRepository: getIt()),
  );
  getIt.registerFactory<LocationBloc>(
    () => LocationBloc(locationRepository: getIt()),
  );
  getIt.registerFactory<LongDistanceBloc>(
    () => LongDistanceBloc(coupleRepository: getIt(), locationRepository: getIt()),
  );
  getIt.registerFactory<BucketBloc>(
    () => BucketBloc(bucketRepository: getIt()),
  );
  getIt.registerFactory<QuestionBloc>(
    () => QuestionBloc(questionRepository: getIt(), coupleRepository: getIt()),
  );
  getIt.registerFactory<MoodInsightsBloc>(
    () => MoodInsightsBloc(moodRepository: getIt(), coupleRepository: getIt(), authRepository: getIt()),
  );
  getIt.registerFactory<SecurityBloc>(
    () => SecurityBloc(encryptionRepository: getIt()),
  );
  getIt.registerFactory<MoodBloc>(
    () => MoodBloc(moodRepository: getIt()),
  );
  getIt.registerFactory<MemoryBloc>(
    () => MemoryBloc(memoryRepository: getIt()),
  );
  getIt.registerFactory<NotificationBloc>(
    () => NotificationBloc(notificationRepository: getIt()),
  );
  getIt.registerFactory<ProfileBloc>(
    () => ProfileBloc(
      authRepository: getIt(),
      coupleRepository: getIt(),
    ),
  );
  getIt.registerFactory<TimelineBloc>(
    () => TimelineBloc(coupleRepository: getIt(), milestoneRepository: getIt()),
  );
  getIt.registerFactory<WidgetsBloc>(
    () => WidgetsBloc(
      moodRepository: getIt(),
      coupleRepository: getIt(),
    ),
  );
}
