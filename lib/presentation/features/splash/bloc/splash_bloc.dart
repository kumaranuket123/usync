import 'package:flutter_bloc/flutter_bloc.dart';

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

    final user = await authRepository.getCurrentUser();

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
