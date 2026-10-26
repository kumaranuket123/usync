part of 'auth_bloc.dart';

sealed class AuthState {}
final class AuthInitial        extends AuthState {}
final class AuthLoading        extends AuthState {}
final class Authenticated      extends AuthState {
  Authenticated(this.user);
  final AppUser user;
}
/// Sign-out in progress (it clears server and local data, so it can take a moment).
final class SigningOut         extends AuthState {
  SigningOut({this.deletingAccount = false});
  final bool deletingAccount;
}
final class Unauthenticated    extends AuthState {}
final class AuthError          extends AuthState {
  AuthError(this.message);
  final String message;
}
