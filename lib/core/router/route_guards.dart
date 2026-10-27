import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:go_router/go_router.dart';

import '../constants/route_names.dart';

abstract final class RouteGuards {
  static final _publicRoutes = {
    RouteNames.splash,
    RouteNames.onboarding,
    RouteNames.login,
  };

  static final _pairingRoutes = {
    RouteNames.pairInvite,
    RouteNames.pairJoin,
    RouteNames.pairSuccess,
  };

  static String? redirect(BuildContext _, GoRouterState state) {
    final path = state.matchedLocation;

    // Splash always renders regardless, and so does the "please update" screen:
    // it is shown to signed-in and signed-out people alike.
    if (path == RouteNames.splash || path == RouteNames.updateRequired) return null;

    final user = Supabase.instance.client.auth.currentUser;
    final isPublic  = _publicRoutes.contains(path);
    final isPairing = _pairingRoutes.contains(path);

    // Unauthenticated — only public routes allowed.
    if (user == null) {
      if (isPublic) return null;
      return RouteNames.login;
    }

    // Authenticated — redirect away from login.
    if (isPublic) return RouteNames.home;

    // Pairing routes are accessible regardless of coupleId
    // (the PairingBloc handles state internally).
    if (isPairing) return null;

    return null;
  }
}
