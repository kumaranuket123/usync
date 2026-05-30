part of 'auth_bloc.dart';

sealed class AuthState {}
final class AuthInitial        extends AuthState {}
final class AuthLoading        extends AuthState {}
final class Authenticated      extends AuthState {
  Authenticated(this.user);
  final AppUser user;
}
final class Unauthenticated    extends AuthState {}
final class AuthError          extends AuthState {
  AuthError(this.message);
  final String message;
}
final class PasswordResetSent  extends AuthState {
  PasswordResetSent(this.email);
  final String email;
}
