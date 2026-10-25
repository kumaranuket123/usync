import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/user.dart';
import '../../../../domain/repositories/i_auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required this.authRepository}) : super(AuthInitial()) {
    on<AuthStateChecked>(_onChecked);
    on<SignInRequested>(_onSignIn);
    on<SignUpRequested>(_onSignUp);
    on<SignOutRequested>(_onSignOut);
    on<PasswordResetRequested>(_onPasswordReset);
  }

  final IAuthRepository authRepository;

  Future<void> _onChecked(AuthStateChecked _, Emitter<AuthState> emit) async {
    try {
      final user = await authRepository.getCurrentUser();
      emit(user != null ? Authenticated(user) : Unauthenticated());
    } catch (err) {
      // Offline with nothing saved yet: stay as we are rather than sign the user out.
      debugPrint('Could not check the signed-in user: $err');
    }
  }

  Future<void> _onSignIn(SignInRequested e, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await authRepository.signIn(e.email, e.password);
      emit(Authenticated(user));
      _saveFcmToken(user.id);
    } catch (err) {
      emit(AuthError(err.toString()));
    }
  }

  Future<void> _onSignUp(SignUpRequested e, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await authRepository.signUp(e.email, e.password, e.username, e.avatarEmoji);
      emit(Authenticated(user));
      _saveFcmToken(user.id);
    } catch (err) {
      emit(AuthError(err.toString()));
    }
  }

  void _saveFcmToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await authRepository.updateFcmToken(uid, token);
    } catch (_) {}
  }

  Future<void> _onSignOut(SignOutRequested _, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    await authRepository.signOut();
    emit(Unauthenticated());
  }

  Future<void> _onPasswordReset(PasswordResetRequested e, Emitter<AuthState> emit) async {
    try {
      await authRepository.sendPasswordReset(e.email);
      emit(PasswordResetSent(e.email));
    } catch (err) {
      emit(AuthError(err.toString()));
    }
  }
}
