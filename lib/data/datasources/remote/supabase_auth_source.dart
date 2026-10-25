import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthSource {
  SupabaseAuthSource({required this.client});
  final SupabaseClient client;

  GoTrueClient get _auth => client.auth;

  Stream<User?> get authStateChanges => _auth.onAuthStateChange.map((s) => s.session?.user);

  User? get currentUser => _auth.currentUser;

  Future<User> signIn(String email, String password) async {
    final res = await _auth.signInWithPassword(email: email, password: password);
    return res.user!;
  }

  /// `username`/`avatar_emoji` go in user metadata; the `handle_new_user`
  /// trigger turns them into the `profiles` row.
  Future<User> signUp(String email, String password, String username, String avatarEmoji) async {
    final res = await _auth.signUp(
      email: email,
      password: password,
      data: {'username': username, 'avatar_emoji': avatarEmoji},
    );
    // No session means the project requires email confirmation.
    if (res.session == null) {
      throw const AuthException('Check your email to confirm your account, then sign in.');
    }
    return res.user!;
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordReset(String email) => _auth.resetPasswordForEmail(email);
}
