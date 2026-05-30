import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../domain/entities/user.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../datasources/local/prefs_source.dart';
import '../datasources/remote/firebase_auth_source.dart';
import '../datasources/remote/firestore_source.dart';
import '../models/user_model.dart';

class AuthRepository implements IAuthRepository {
  AuthRepository({
    required this.authSource,
    required this.firestoreSource,
    required this.prefsSource,
  });

  final FirebaseAuthSource authSource;
  final FirestoreSource    firestoreSource;
  final PrefsSource        prefsSource;

  @override
  Stream<AppUser?> watchAuthState() {
    return authSource.authStateChanges.asyncMap((firebaseUser) async {
      if (firebaseUser == null) return null;
      return _fetchUser(firebaseUser.uid);
    });
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    final cu = authSource.currentUser;
    if (cu == null) return null;
    return _fetchUser(cu.uid);
  }

  @override
  Future<AppUser> signIn(String email, String password) async {
    final cred = await authSource.signIn(email, password);
    return _fetchUser(cred.user!.uid);
  }

  @override
  Future<AppUser> signUp(String email, String password, String username, String avatarEmoji) async {
    final cred = await authSource.signUp(email, password);
    final uid  = cred.user!.uid;
    final user = UserModel(
      id:          uid,
      username:    username,
      email:       email,
      avatarEmoji: avatarEmoji,
      createdAt:   DateTime.now(),
    );
    await firestoreSource.userDoc(uid).set(user.toJson());
    return user;
  }

  @override
  Future<void> signOut() async {
    // Clear FCM token from Firestore and revoke it on device before signing out
    final uid = authSource.currentUser?.uid;
    if (uid != null) {
      try {
        await firestoreSource.userDoc(uid).update({'fcmToken': null});
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
    await authSource.signOut();
    await prefsSource.clearSession();
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      authSource.sendPasswordReset(email);

  @override
  Future<AppUser?> getUserById(String uid) async {
    try {
      return await _fetchUser(uid);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> updateFcmToken(String uid, String token) =>
      firestoreSource.userDoc(uid).update({'fcmToken': token});

  Future<AppUser> _fetchUser(String uid) async {
    final snap = await firestoreSource.userDoc(uid).get();
    if (!snap.exists) throw Exception('User document not found: $uid');
    return UserModel.fromJson({'id': uid, ...snap.data()!});
  }
}
