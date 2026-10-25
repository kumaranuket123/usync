import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/features/auth/screens/login_screen.dart';
import '../../presentation/features/auth/screens/register_screen.dart';
import '../../presentation/features/canvas/screens/canvas_screen.dart';
import '../../presentation/features/home/screens/home_screen.dart';
import '../../presentation/features/location/screens/location_screen.dart';
import '../../presentation/features/memory/screens/memory_detail_screen.dart';
import '../../presentation/features/memory/screens/memory_space_screen.dart';
import '../../presentation/features/mood/screens/mood_screen.dart';
import '../../presentation/features/notifications/screens/notifications_screen.dart';
import '../../presentation/features/onboarding/screens/onboarding_screen.dart';
import '../../presentation/features/pairing/screens/pair_invite_screen.dart';
import '../../presentation/features/pairing/screens/pair_join_screen.dart';
import '../../presentation/features/pairing/screens/pair_success_screen.dart';
import '../../presentation/features/profile/screens/profile_screen.dart';
import '../../presentation/features/settings/screens/settings_screen.dart';
import '../../presentation/features/settings/screens/theme_selection_screen.dart';
import '../../presentation/features/splash/screens/splash_screen.dart';
import '../../presentation/features/timeline/screens/timeline_screen.dart';
import '../../presentation/features/touch_sync/screens/touch_sync_screen.dart';
import '../../presentation/features/widgets_showcase/screens/widgets_screen.dart';
import '../../presentation/shared/widgets/usync_bottom_nav.dart';
import '../constants/route_names.dart';
import 'route_guards.dart';

abstract final class AppRouter {
  static final _rootKey = GlobalKey<NavigatorState>();
  static final _shellKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: RouteNames.splash,
    redirect: RouteGuards.redirect,
    routes: [
      // ── Pre-auth ─────────────────────────────────────────────
      GoRoute(
        path: RouteNames.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: RouteNames.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: RouteNames.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteNames.register,
        builder: (_, __) => const RegisterScreen(),
      ),

      // ── Pairing ───────────────────────────────────────────────
      GoRoute(
        path: RouteNames.pairInvite,
        builder: (_, __) => const PairInviteScreen(),
      ),
      GoRoute(
        path: RouteNames.pairJoin,
        builder: (_, __) => const PairJoinScreen(),
      ),
      GoRoute(
        path: RouteNames.pairSuccess,
        builder: (_, __) => const PairSuccessScreen(),
      ),

      // ── Main shell (bottom nav) ────────────────────────────────
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) => UsyncShell(child: child),
        routes: [
          GoRoute(
            path: RouteNames.home,
            builder: (_, __) => const HomeScreen(),
          ),
          GoRoute(
            path: RouteNames.memories,
            builder: (_, __) => const MemorySpaceScreen(),
          ),
          GoRoute(
            path: RouteNames.canvas,
            builder: (_, __) => const CanvasScreen(),
          ),
          GoRoute(
            path: RouteNames.widgets,
            builder: (_, __) => const WidgetsScreen(),
          ),
          GoRoute(
            path: RouteNames.profile,
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      ),

      // ── Pushed above shell ────────────────────────────────────
      GoRoute(
        path: RouteNames.touchSync,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const TouchSyncScreen(),
      ),
      GoRoute(
        path: RouteNames.location,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const LocationScreen(),
      ),
      GoRoute(
        path: RouteNames.mood,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const MoodScreen(),
      ),
      GoRoute(
        path: '/memories/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => MemoryDetailScreen(
          memoryId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: RouteNames.notifications,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: RouteNames.timeline,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const TimelineScreen(),
      ),
      GoRoute(
        path: RouteNames.settings,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: RouteNames.themes,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const ThemeSelectionScreen(),
      ),
    ],
  );
}
