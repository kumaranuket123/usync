import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/local/hive_source.dart';
import '../../data/datasources/local/prefs_source.dart';
import '../../data/datasources/remote/firebase_auth_source.dart';
import '../../data/datasources/remote/firestore_source.dart';
import '../../data/datasources/remote/rtdb_source.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/canvas_repository.dart';
import '../../data/repositories/couple_repository.dart';
import '../../data/repositories/memory_repository.dart';
import '../../data/repositories/mood_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/touch_repository.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../../domain/repositories/i_canvas_repository.dart';
import '../../domain/repositories/i_couple_repository.dart';
import '../../domain/repositories/i_memory_repository.dart';
import '../../domain/repositories/i_mood_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
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
import '../../presentation/features/touch_sync/bloc/touch_sync_bloc.dart';
import '../../presentation/features/widgets_showcase/bloc/widgets_bloc.dart';

final GetIt getIt = GetIt.instance;

Future<void> setupLocator() async {
  // ── External ──────────────────────────────────────────────────
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);
  getIt.registerSingleton<FirebaseAuth>(FirebaseAuth.instance);
  getIt.registerSingleton<FirebaseFirestore>(FirebaseFirestore.instance);
  getIt.registerSingleton<FirebaseDatabase>(FirebaseDatabase.instance);

  // ── Data sources ──────────────────────────────────────────────
  getIt.registerLazySingleton<FirebaseAuthSource>(
    () => FirebaseAuthSource(auth: getIt()),
  );
  getIt.registerLazySingleton<FirestoreSource>(
    () => FirestoreSource(firestore: getIt()),
  );
  getIt.registerLazySingleton<RtdbSource>(
    () => RtdbSource(database: getIt()),
  );
  getIt.registerLazySingleton<HiveSource>(() => HiveSource());
  getIt.registerLazySingleton<PrefsSource>(
    () => PrefsSource(prefs: getIt()),
  );

  // ── Repositories ──────────────────────────────────────────────
  getIt.registerLazySingleton<IAuthRepository>(
    () => AuthRepository(
      authSource: getIt(),
      firestoreSource: getIt(),
      prefsSource: getIt(),
    ),
  );
  getIt.registerLazySingleton<ICoupleRepository>(
    () => CoupleRepository(
      firestoreSource: getIt(),
      rtdbSource: getIt(),
    ),
  );
  getIt.registerLazySingleton<IMoodRepository>(
    () => MoodRepository(
      firestoreSource: getIt(),
      rtdbSource: getIt(),
    ),
  );
  getIt.registerLazySingleton<IMemoryRepository>(
    () => MemoryRepository(firestoreSource: getIt()),
  );
  getIt.registerLazySingleton<ICanvasRepository>(
    () => CanvasRepository(rtdbSource: getIt()),
  );
  getIt.registerLazySingleton<ITouchRepository>(
    () => TouchRepository(rtdbSource: getIt()),
  );
  getIt.registerLazySingleton<INotificationRepository>(
    () => NotificationRepository(firestoreSource: getIt()),
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
    () => TimelineBloc(coupleRepository: getIt()),
  );
  getIt.registerFactory<WidgetsBloc>(
    () => WidgetsBloc(
      moodRepository: getIt(),
      coupleRepository: getIt(),
    ),
  );
}
