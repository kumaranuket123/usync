part of 'auth_bloc.dart';

sealed class AuthEvent { const AuthEvent(); }
final class AuthStateChecked extends AuthEvent { const AuthStateChecked() : super(); }
final class GoogleSignInRequested extends AuthEvent { const GoogleSignInRequested() : super(); }
final class SignOutRequested extends AuthEvent { const SignOutRequested() : super(); }
/// The session ended without the user asking (the server revoked it).
final class SessionEnded extends AuthEvent { const SessionEnded() : super(); }
