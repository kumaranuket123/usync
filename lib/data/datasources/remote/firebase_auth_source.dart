import 'package:firebase_auth/firebase_auth.dart';


class FirebaseAuthSource {
  FirebaseAuthSource({required this.auth});
  final FirebaseAuth auth;

  Stream<User?> get authStateChanges => auth.authStateChanges();

  User? get currentUser => auth.currentUser;

  Future<UserCredential> signIn(String email, String password) =>
      auth.signInWithEmailAndPassword(email: email, password: password);

  Future<UserCredential> signUp(String email, String password) =>
      auth.createUserWithEmailAndPassword(email: email, password: password);

  Future<void> signOut() => auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      auth.sendPasswordResetEmail(email: email);
}
