import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/google_config.dart';

class SupabaseAuthSource {
  SupabaseAuthSource({required this.client});
  final SupabaseClient client;

  GoTrueClient get _auth => client.auth;

  Stream<User?> get authStateChanges => _auth.onAuthStateChange.map((s) => s.session?.user);

  /// Fires when the session ends, whether the user signed out or the server
  /// revoked it (account removed, refresh failed).
  Stream<void> get signedOut =>
      _auth.onAuthStateChange.where((s) => s.event == AuthChangeEvent.signedOut);

  User? get currentUser => _auth.currentUser;

  Future<void>? _googleInit;

  Future<void> _ensureGoogleInit() => _googleInit ??= GoogleSignIn.instance.initialize(
        serverClientId: GoogleConfig.webClientId.isEmpty ? null : GoogleConfig.webClientId,
        clientId:       GoogleConfig.iosClientId.isEmpty ? null : GoogleConfig.iosClientId,
      );

  /// Native Google account picker, then the ID token is exchanged for a Supabase
  /// session. A first sign-in creates the account (the `handle_new_user` trigger
  /// makes the `profiles` row). Throws [GoogleSignInException] if cancelled.
  Future<User> signInWithGoogle() async {
    await _ensureGoogleInit();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw const AuthException('Google did not return an ID token.');
    final res = await _auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
    return res.user!;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    // Forget the chosen Google account so the next sign-in shows the picker.
    try {
      await _ensureGoogleInit();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
