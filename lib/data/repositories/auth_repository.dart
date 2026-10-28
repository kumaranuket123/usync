import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../core/services/home_widget_service.dart';
import '../../core/services/outbox_service.dart';
import '../../core/utils/network_errors.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../datasources/local/identity_cache.dart';
import '../datasources/local/local_memory_images.dart';
import '../datasources/local/prefs_source.dart';
import '../datasources/local/session_cache.dart';
import '../datasources/remote/couple_channel_source.dart';
import '../datasources/remote/storage_source.dart';
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
    required this.channels,
    required this.storage,
    this.wipeKeys,
    this.cancelReminders,
  });

  final SupabaseAuthSource authSource;
  final SupabaseClient     client;
  final PrefsSource        prefsSource;
  final SessionCache       sessionCache;
  final OutboxService      outbox;
  final IdentityCache      identity;
  final CoupleChannelSource channels;
  final StorageSource       storage;
  /// Removes this account's encryption keys from the phone (account deletion). Optional so tests can skip it.
  final Future<void> Function(String userId)? wipeKeys;
  /// Removes the date reminders scheduled on this phone.
  final Future<void> Function()? cancelReminders;

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
  Future<AppUser> signInWithGoogle() async {
    final user = await authSource.signInWithGoogle();
    identity.clear();
    return _fetchUser(user.id);
  }

  @override
  Stream<void> get signedOut => authSource.signedOut.map((_) {
        // The session may already be gone (revoked), so only local state can be cleaned here.
        _clearLocalAccountState();
      });

  @override
  Future<void> signOut() async {
    final uid = authSource.currentUser?.id;
    if (uid != null) {
      // Server-side clean-up needs the session, so it comes before signing out.
      // Every step is best effort and independent: one failing (say, offline)
      // must not skip the others.
      // Stop showing this account's location to the partner.
      await _quietly(() => client.from('locations').delete().eq('user_id', uid));
      // Only THIS device is removed; the account's other phones keep their pushes.
      String? token;
      await _quietly(() async => token = await FirebaseMessaging.instance.getToken());
      if (token != null) {
        await _quietly(() => client.from('device_tokens').delete().eq('fcm_token', token!));
      }
      await prefsSource.clearFcmSaved(uid);
      // Always invalidate the device's push token, even if the server row could not
      // be removed: otherwise the old account keeps getting pushes on this phone.
      // (A leftover row then holds a dead token, which the push function drops.)
      await _quietly(() => FirebaseMessaging.instance.deleteToken());
    }
    // Locally the session is removed first; a network error while telling the
    // server only means the revoke did not reach it.
    await _quietly(authSource.signOut);
    await _clearLocalAccountState();
  }

  @override
  Future<void> deleteAccount() async {
    final uid = authSource.currentUser?.id;
    if (uid == null) return;
    // Images first: only an active couple member may delete them.
    final coupleId = (await getCurrentUser())?.coupleId;
    if (coupleId != null) await storage.removeFolder(coupleId);
    await client.rpc('delete_my_account');
    await _quietly(LocalMemoryImages.deleteAll);
    // The keys were only ever for this account: nothing may be left on this phone.
    final wipe = wipeKeys;
    if (wipe != null) await _quietly(() => wipe(uid));
    // The account is gone; this clears this device (push token, caches, session).
    await signOut();
  }

  /// Nothing of this account may stay behind for the next one.
  Future<void> _clearLocalAccountState() async {
    await prefsSource.clearSession();
    await sessionCache.clear();
    await outbox.clear();
    // The home-screen doodle widget would otherwise keep showing this couple's drawing.
    await _quietly(() => HomeWidgetService.refresh(const []));
    final cancel = cancelReminders;
    if (cancel != null) await _quietly(cancel);
    identity.clear();
    // The live channel belongs to this session; the next one needs its own.
    channels.close();
  }

  static Future<void> _quietly(Future<Object?> Function() step) async {
    try {
      await step();
    } catch (_) {}
  }

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
    // The user switched push notifications off in Settings: do not register this device.
    if (!prefsSource.notificationsEnabled) return;
    // The app does this at every start; the server already has it unless the
    // token changed, so only write when it did (or once in a while to refresh).
    final saved = prefsSource.fcmSaved(uid);
    if (saved != null &&
        saved.token == token &&
        DateTime.now().millisecondsSinceEpoch - saved.savedAt < _tokenRefreshEvery.inMilliseconds) {
      return;
    }
    // A function, not an upsert: it also handles a phone that changed hands
    // (same token, new account) and keeps a few devices per account.
    await client.rpc('register_device_token', params: {'p_token': token});
    await prefsSource.setFcmSaved(uid, token);
  }

  static const _tokenRefreshEvery = Duration(days: 14);

  @override
  Future<void> updateProfile(String uid, {String? username, String? avatarEmoji}) async {
    final changes = {
      if (username != null)    'username':     username,
      if (avatarEmoji != null) 'avatar_emoji': avatarEmoji,
    };
    if (changes.isEmpty) return;
    // select() so a row the policy refused to touch is an error, not a silent no-op.
    final rows = await client.from('profiles').update(changes).eq('id', uid).select();
    if (rows.isEmpty) throw Exception('Could not update the profile');
    identity.profiles.invalidate(uid);
    if (username != null) {
      // The name in the session is what notifications are signed with
      // ("[name] is feeling…"), so keep it in step. Best effort: the profile is
      // the source of truth.
      try {
        await client.auth.updateUser(UserAttributes(data: {'username': username}));
      } catch (_) {}
    }
  }

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
