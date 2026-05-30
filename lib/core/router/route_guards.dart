import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../constants/route_names.dart';

abstract final class RouteGuards {
  static final _publicRoutes = {
    RouteNames.splash,
    RouteNames.onboarding,
    RouteNames.login,
    RouteNames.register,
  };

  static final _pairingRoutes = {
    RouteNames.pairInvite,
    RouteNames.pairJoin,
    RouteNames.pairSuccess,
  };

  static Future<String?> redirect(_, GoRouterState state) async {
    final path = state.matchedLocation;

    // Splash always renders regardless.
    if (path == RouteNames.splash) return null;

    final user = FirebaseAuth.instance.currentUser;
    final isPublic  = _publicRoutes.contains(path);
    final isPairing = _pairingRoutes.contains(path);

    // Unauthenticated — only public routes allowed.
    if (user == null) {
      if (isPublic) return null;
      return RouteNames.login;
    }

    // Authenticated — redirect away from login/register.
    if (isPublic) return RouteNames.home;

    // Pairing routes are accessible regardless of coupleId
    // (the PairingBloc handles state internally).
    if (isPairing) return null;

    return null;
  }
}
