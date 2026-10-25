import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/repositories/touch_repository.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../../domain/repositories/i_canvas_repository.dart';
import '../../domain/repositories/i_couple_repository.dart';
import '../../domain/repositories/i_memory_repository.dart';
import '../../domain/repositories/i_mood_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../../domain/repositories/i_location_repository.dart';
import '../../domain/repositories/i_touch_repository.dart';
import '../../presentation/features/auth/bloc/auth_bloc.dart';
import '../../presentation/features/canvas/bloc/canvas_bloc.dart';
import '../../presentation/features/home/bloc/home_bloc.dart';
import '../../presentation/features/memory/bloc/memory_bloc.dart';
import '../../presentation/features/mood/bloc/mood_bloc.dart';
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

  // ── Repositories ──────────────────────────────────────────────
  getIt.registerLazySingleton<IAuthRepository>(
    () => AuthRepository(
      authSource: getIt(),
      client: getIt(),
      prefsSource: getIt(),
    ),
  );
  getIt.registerLazySingleton<ICoupleRepository>(
    () => CoupleRepository(
      client: getIt(),
      channelSource: getIt(),
      notifications: getIt(),
    ),
  );
  getIt.registerLazySingleton<IMoodRepository>(
    () => MoodRepository(
      client: getIt(),
      notifications: getIt(),
    ),
  );
  getIt.registerLazySingleton<IMemoryRepository>(
    () => MemoryRepository(client: getIt(), storage: getIt(), notifications: getIt()),
  );
  getIt.registerLazySingleton<ICanvasRepository>(
    () => CanvasRepository(client: getIt(), channelSource: getIt(), storage: getIt()),
  );
  getIt.registerLazySingleton<ITouchRepository>(
    () => TouchRepository(channelSource: getIt()),
  );
  getIt.registerLazySingleton<ILocationRepository>(
    () => LocationRepository(client: getIt(), prefs: getIt(), notifications: getIt()),
  );
  getIt.registerLazySingleton<INotificationRepository>(
    () => NotificationRepository(client: getIt()),
  );

  // ── BLoCs (factory — new instance per registration request) ───
  getIt.registerFactory<AuthBloc>(
    () => AuthBloc(authRepository: getIt()),
  );
  getIt.registerFactory<SettingsBloc>(
    () => SettingsBloc(prefsSource: getIt()),
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
    () => CanvasBloc(canvasRepository: getIt()),
  );
  getIt.registerFactory<TouchSyncBloc>(
    () => TouchSyncBloc(touchRepository: getIt()),
  );
  getIt.registerFactory<LocationBloc>(
    () => LocationBloc(locationRepository: getIt()),
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
      memoryRepository: getIt(),
    ),
  );
  getIt.registerFactory<TimelineBloc>(
    () => TimelineBloc(coupleRepository: getIt(), client: getIt()),
  );
  getIt.registerFactory<WidgetsBloc>(
    () => WidgetsBloc(
      moodRepository: getIt(),
      coupleRepository: getIt(),
    ),
  );
}
