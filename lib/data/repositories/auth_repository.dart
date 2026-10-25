import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../core/services/outbox_service.dart';
import '../../core/utils/network_errors.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../datasources/local/identity_cache.dart';
import '../datasources/local/prefs_source.dart';
import '../datasources/local/session_cache.dart';
import '../datasources/remote/supabase_auth_source.dart';
import '../models/user_model.dart';

class AuthRepository implements IAuthRepository {
  AuthRepository({
    required this.authSource,
    required this.client,
    required this.prefsSource,
    required this.sessionCache,
    required this.outbox,
    required this.identity,
  });

  final SupabaseAuthSource authSource;
  final SupabaseClient     client;
  final PrefsSource        prefsSource;
  final SessionCache       sessionCache;
  final OutboxService      outbox;
  final IdentityCache      identity;

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
    identity.clear();
    return _fetchUser(user.id);
  }

  @override
  Future<AppUser> signUp(String email, String password, String username, String avatarEmoji) async {
    final user = await authSource.signUp(email, password, username, avatarEmoji);
    identity.clear();
    return _fetchUser(user.id);
  }

  @override
  Future<void> signOut() async {
    // Drop the FCM token server-side and on the device before signing out.
    final uid = authSource.currentUser?.id;
    if (uid != null) {
      try {
        await client.from('device_tokens').delete().eq('user_id', uid);
        await prefsSource.clearFcmSaved(uid);
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
    await authSource.signOut();
    await prefsSource.clearSession();
    // Nothing of this account may stay behind for the next one.
    await sessionCache.clear();
    await outbox.clear();
    identity.clear();
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
  Future<void> updateFcmToken(String uid, String token) async {
    // The app does this at every start; the server already has it unless the
    // token changed, so only write when it did (or once in a while to refresh).
    final saved = prefsSource.fcmSaved(uid);
    if (saved != null &&
        saved.token == token &&
        DateTime.now().millisecondsSinceEpoch - saved.savedAt < _tokenRefreshEvery.inMilliseconds) {
      return;
    }
    await client.from('device_tokens').upsert({
      'user_id':    uid,
      'fcm_token':  token,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await prefsSource.setFcmSaved(uid, token);
  }

  static const _tokenRefreshEvery = Duration(days: 14);

  /// Profiles are remembered for a few minutes, so opening a screen does not ask
  /// the server again for someone we already know.
  Future<AppUser> _fetchUser(String uid) => identity.profiles.get(uid, () => _loadUser(uid));

  /// Reads the profile and saves it on the device; without a connection the last
  /// saved copy is used, so the app can still start.
  Future<AppUser> _loadUser(String uid) async {
    try {
      final row = await client.from('profiles').select().eq('id', uid).maybeSingle();
      if (row == null) throw Exception('Profile not found: $uid');
      await sessionCache.put(SessionCache.profile(uid), row);
      return UserModel.fromProfile(row);
    } catch (e) {
      final cached = isNetworkError(e) ? sessionCache.getMap(SessionCache.profile(uid)) : null;
      if (cached != null) return UserModel.fromProfile(cached);
      rethrow;
    }
  }
}
