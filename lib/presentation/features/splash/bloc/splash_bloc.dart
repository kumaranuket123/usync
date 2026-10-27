import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../../../domain/entities/user.dart';
import '../../../../domain/repositories/i_access_repository.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../data/datasources/local/prefs_source.dart';

part 'splash_event.dart';
part 'splash_state.dart';

class SplashBloc extends Bloc<SplashEvent, SplashState> {
  SplashBloc({
    required this.authRepository,
    required this.prefsSource,
    required this.accessRepository,
    this.minDisplay = const Duration(seconds: 3),
    Future<int> Function()? buildNumber,
  })  : _buildNumber = buildNumber ?? _installedBuild,
        super(SplashLoading()) {
    on<SplashStarted>(_onStarted);
  }

  final IAuthRepository authRepository;
  final PrefsSource     prefsSource;
  final IAccessRepository accessRepository;
  /// How long the splash stays up at least.
  final Duration        minDisplay;
  final Future<int> Function() _buildNumber;

  static Future<int> _installedBuild() async =>
      int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  Future<void> _onStarted(SplashStarted event, Emitter<SplashState> emit) async {
    // Ask the server while the logo plays. This build may be too old to be used at all.
    final configFuture = accessRepository.getConfig();
    await Future.delayed(minDisplay);
    final config = await configFuture;
    if (config.isUpdateRequired(await _buildNumber())) {
      emit(SplashNavigating(SplashDestination.updateRequired));
      return;
    }

    AppUser? user;
    try {
      user = await authRepository.getCurrentUser();
    } catch (err) {
      // No connection and nothing saved from an earlier run: if there is a
      // signed-in session, go on to Home (it explains the problem) rather
      // than stay on this screen.
      debugPrint('Splash could not load the profile: $err');
      final signedIn = Supabase.instance.client.auth.currentUser != null;
      emit(SplashNavigating(signedIn ? SplashDestination.home : SplashDestination.login));
      return;
    }

    if (user == null) {
      final seen = prefsSource.onboardingSeen;
      emit(SplashNavigating(seen ? SplashDestination.login : SplashDestination.onboarding));
      return;
    }

    if (user.coupleId == null) {
      emit(SplashNavigating(SplashDestination.pairInvite));
    } else {
      emit(SplashNavigating(SplashDestination.home));
    }
  }
}
