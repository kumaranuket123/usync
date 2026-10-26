import '../entities/user.dart';

abstract interface class IAuthRepository {
  Stream<AppUser?> watchAuthState();
  Future<AppUser>  signInWithGoogle();
  Future<void>     signOut();
  /// Emits when the session ends for any reason (including the server revoking it).
  Stream<void>     get signedOut;
  Future<AppUser?> getCurrentUser();
  Future<AppUser?> getUserById(String uid);
  Future<void>     updateFcmToken(String uid, String token);
  /// Changes the signed-in user's name and/or avatar (what their partner sees).
  /// Only the fields given are changed.
  Future<void>     updateProfile(String uid, {String? username, String? avatarEmoji});
}
