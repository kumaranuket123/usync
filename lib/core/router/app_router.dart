import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/memory.dart';
import '../../presentation/features/auth/screens/login_screen.dart';
import '../../presentation/features/canvas/screens/canvas_screen.dart';
import '../../presentation/features/home/screens/home_screen.dart';
import '../../presentation/features/location/screens/location_screen.dart';
import '../../presentation/features/memory/screens/memory_detail_screen.dart';
import '../../presentation/features/memory/screens/memory_space_screen.dart';
import '../../presentation/features/mood/screens/mood_screen.dart';
import '../../presentation/features/mood_insights/screens/mood_insights_screen.dart';
import '../../presentation/features/activity/screens/activity_screen.dart';
import '../../presentation/features/bucket/screens/bucket_list_screen.dart';
import '../../presentation/features/games/screens/cards_screen.dart';
import '../../presentation/features/games/screens/games_hub_screen.dart';
import '../../presentation/features/games/screens/quiz_screen.dart';
import '../../presentation/features/games/screens/tic_tac_toe_screen.dart';
import '../../presentation/features/games/screens/would_you_rather_screen.dart';
import '../../presentation/features/question/screens/question_screen.dart';
import '../../presentation/features/notifications/screens/notifications_screen.dart';
import '../../presentation/features/onboarding/screens/onboarding_screen.dart';
import '../../presentation/features/pairing/screens/pair_invite_screen.dart';
import '../../presentation/features/pairing/screens/pair_join_screen.dart';
import '../../presentation/features/pairing/screens/pair_success_screen.dart';
import '../../presentation/features/profile/screens/profile_screen.dart';
import '../../presentation/features/access/screens/paywall_screen.dart';
import '../../presentation/features/access/screens/update_required_screen.dart';
import '../../presentation/features/security/screens/security_screen.dart';
import '../../presentation/features/settings/screens/about_screen.dart';
import '../../presentation/features/settings/screens/alert_sounds_screen.dart';
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
        path: RouteNames.updateRequired,
        builder: (_, __) => const UpdateRequiredScreen(),
      ),
      GoRoute(
        path: RouteNames.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: RouteNames.login,
        builder: (_, __) => const LoginScreen(),
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
            path: RouteNames.activity,
            builder: (_, __) => const ActivityScreen(),
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
        path: RouteNames.widgets,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const WidgetsScreen(),
      ),
      GoRoute(
        path: RouteNames.bucketList,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const BucketListScreen(),
      ),
      GoRoute(
        path: RouteNames.games,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const GamesHubScreen(),
      ),
      GoRoute(
        path: RouteNames.ticTacToe,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const TicTacToeScreen(),
      ),
      GoRoute(
        path: RouteNames.cards,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const CardsScreen(),
      ),
      GoRoute(
        path: RouteNames.quiz,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const QuizScreen(),
      ),
      GoRoute(
        path: RouteNames.wouldYouRather,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const WouldYouRatherScreen(),
      ),
      GoRoute(
        path: RouteNames.question,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const QuestionScreen(),
      ),
      GoRoute(
        path: RouteNames.moodInsights,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const MoodInsightsScreen(),
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
          // Pushed from the Memories list with the memory attached.
          memory:   state.extra is Memory ? state.extra as Memory : null,
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
        path: RouteNames.paywall,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const PaywallScreen(),
      ),
      GoRoute(
        path: RouteNames.security,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const SecurityScreen(),
      ),
      GoRoute(
        path: RouteNames.about,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const AboutScreen(),
      ),
      GoRoute(
        path: RouteNames.alertSounds,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const AlertSoundsScreen(),
      ),
      GoRoute(
        path: RouteNames.themes,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const ThemeSelectionScreen(),
      ),
    ],
  );
}
