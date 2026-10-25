import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../domain/entities/user.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../datasources/local/prefs_source.dart';
import '../datasources/remote/supabase_auth_source.dart';
import '../models/user_model.dart';

class AuthRepository implements IAuthRepository {
  AuthRepository({
    required this.authSource,
    required this.client,
    required this.prefsSource,
  });

  final SupabaseAuthSource authSource;
  final SupabaseClient     client;
  final PrefsSource        prefsSource;

  @override
  Stream<AppUser?> watchAuthState() {
    return authSource.authStateChanges.asyncMap((user) async {
      if (user == null) return null;
      return _fetchUser(user.id);
    });
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    final cu = authSource.currentUser;
    if (cu == null) return null;
    return _fetchUser(cu.id);
  }

  @override
  Future<AppUser> signIn(String email, String password) async {
    final user = await authSource.signIn(email, password);
    return _fetchUser(user.id);
  }

  @override
  Future<AppUser> signUp(String email, String password, String username, String avatarEmoji) async {
    final user = await authSource.signUp(email, password, username, avatarEmoji);
    return _fetchUser(user.id);
  }

  @override
  Future<void> signOut() async {
    // Drop the FCM token server-side and on the device before signing out.
    final uid = authSource.currentUser?.id;
    if (uid != null) {
      try {
        await client.from('device_tokens').delete().eq('user_id', uid);
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
      client.from('device_tokens').upsert({
        'user_id':    uid,
        'fcm_token':  token,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  Future<AppUser> _fetchUser(String uid) async {
    final row = await client.from('profiles').select().eq('id', uid).maybeSingle();
    if (row == null) throw Exception('Profile not found: $uid');
    return UserModel.fromProfile(row);
  }
}
