import '../entities/user.dart';

abstract interface class IAuthRepository {
  Stream<AppUser?> watchAuthState();
  Future<AppUser>  signIn(String email, String password);
  Future<AppUser>  signUp(String email, String password, String username, String avatarEmoji);
  Future<void>     signOut();
  Future<void>     sendPasswordReset(String email);
  Future<AppUser?> getCurrentUser();
  Future<AppUser?> getUserById(String uid);
  Future<void>     updateFcmToken(String uid, String token);
  /// Changes the signed-in user's name and/or avatar (what their partner sees).
  /// Only the fields given are changed.
  Future<void>     updateProfile(String uid, {String? username, String? avatarEmoji});
}
