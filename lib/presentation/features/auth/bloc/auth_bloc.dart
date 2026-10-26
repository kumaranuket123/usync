import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/utils/auth_messages.dart';
import '../../../../domain/entities/user.dart';
import '../../../../domain/repositories/i_auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required this.authRepository}) : super(AuthInitial()) {
    on<AuthStateChecked>(_onChecked);
    on<GoogleSignInRequested>(_onGoogleSignIn);
    on<SignOutRequested>(_onSignOut);
    on<SessionEnded>((_, emit) {
      if (state is Authenticated) emit(Unauthenticated());
    });
    // The server can end a session (revoked, password changed elsewhere): the
    // app must notice and go back to sign-in instead of failing quietly.
    _signedOutSub = authRepository.signedOut.listen((_) {
      if (!isClosed) add(const SessionEnded());
    });
  }

  final IAuthRepository authRepository;
  StreamSubscription<void>? _signedOutSub;

  @override
  Future<void> close() {
    _signedOutSub?.cancel();
    return super.close();
  }

  Future<void> _onChecked(AuthStateChecked _, Emitter<AuthState> emit) async {
    try {
      final user = await authRepository.getCurrentUser();
      emit(user != null ? Authenticated(user) : Unauthenticated());
    } catch (err) {
      // Offline with nothing saved yet: stay as we are rather than sign the user out.
      debugPrint('Could not check the signed-in user: $err');
    }
  }

  Future<void> _onGoogleSignIn(GoogleSignInRequested _, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await authRepository.signInWithGoogle();
      emit(Authenticated(user));
      _saveFcmToken(user.id);
    } on GoogleSignInException catch (err) {
      // Closing the account picker is not an error worth a message.
      final cancelled = err.code == GoogleSignInExceptionCode.canceled ||
          err.code == GoogleSignInExceptionCode.interrupted;
      debugPrint('Google sign-in failed: ${err.code} ${err.description}');
      emit(cancelled ? Unauthenticated() : AuthError(
        kDebugMode ? 'Google sign-in failed: ${err.code.name} ${err.description ?? ''}'.trim()
                   : 'Google sign-in failed. Please try again.',
      ));
    } catch (err) {
      debugPrint('Sign-in failed: $err');
      emit(AuthError(friendlyAuthMessage(err)));
    }
  }

  void _saveFcmToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await authRepository.updateFcmToken(uid, token);
    } catch (_) {}
  }

  Future<void> _onSignOut(SignOutRequested _, Emitter<AuthState> emit) async {
    emit(SigningOut());
    await authRepository.signOut();
    emit(Unauthenticated());
  }
}
