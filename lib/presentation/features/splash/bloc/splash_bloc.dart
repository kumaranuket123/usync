import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../../../domain/entities/user.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../data/datasources/local/prefs_source.dart';

part 'splash_event.dart';
part 'splash_state.dart';

class SplashBloc extends Bloc<SplashEvent, SplashState> {
  SplashBloc({required this.authRepository, required this.prefsSource})
      : super(SplashLoading()) {
    on<SplashStarted>(_onStarted);
  }

  final IAuthRepository authRepository;
  final PrefsSource     prefsSource;

  Future<void> _onStarted(SplashStarted event, Emitter<SplashState> emit) async {
    await Future.delayed(const Duration(seconds: 3));

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
