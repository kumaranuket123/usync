part of 'auth_bloc.dart';

sealed class AuthEvent { const AuthEvent(); }
final class AuthStateChecked extends AuthEvent { const AuthStateChecked() : super(); }
final class SignInRequested extends AuthEvent {
  const SignInRequested({required this.email, required this.password}) : super();
  final String email, password;
}
final class SignUpRequested extends AuthEvent {
  const SignUpRequested({required this.email, required this.password,
    required this.username, required this.avatarEmoji}) : super();
  final String email, password, username, avatarEmoji;
}
final class SignOutRequested extends AuthEvent { const SignOutRequested() : super(); }
/// The session ended without the user asking (the server revoked it).
final class SessionEnded extends AuthEvent { const SessionEnded() : super(); }
final class PasswordResetRequested extends AuthEvent {
  const PasswordResetRequested({required this.email}) : super();
  final String email;
}
