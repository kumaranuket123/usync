import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/crypto/content_cipher.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/local/notification_local_source.dart';
import '../models/notification_model.dart';

class NotificationRepository implements INotificationRepository {
  /// [localSource] is the saved list; a background task that only sends notifications (no local storage
  /// there) leaves it out.
  NotificationRepository({required this.client, required this.cipher, NotificationLocalSource? localSource})
      : _localSource = localSource;
  final SupabaseClient client;
  final ContentCipher  cipher;
  final NotificationLocalSource? _localSource;

  NotificationLocalSource get local =>
      _localSource ?? (throw StateError('This NotificationRepository has no local storage'));
  final _uuid = const Uuid();

  final _senderNames = <String, String>{};

  /// The sender's display name. The signed-in user's own name is already in
  /// their session (it was given at sign-up), so the common case costs no
  /// request; anyone else is looked up once and remembered.
  Future<String> _senderName(String uid) async {
    final user = client.auth.currentUser;
    if (user != null && user.id == uid) {
      final name = user.userMetadata?['username'];
      if (name is String && name.isNotEmpty) return name;
    }
    final known = _senderNames[uid];
    if (known != null) return known;
    final row  = await client.from('profiles').select('username').eq('id', uid).maybeSingle();
    final name = row?['username'] as String?;
    if (name == null) return 'Your partner';
    return _senderNames[uid] = name;
  }

  /// The ones we sent are for the partner; only the partner's are saved here.
  String? get _me => client.auth.currentUser?.id;

  /// Touch and location alerts repeat every time someone taps or looks, which
  /// floods the list with identical lines. Keep only the newest one per sender
  /// and kind; other types (doodles, moods, milestones) are distinct events.
  /// Takes and returns items newest first.
  static List<NotificationItem> _collapseRepeats(List<NotificationItem> items) {
    const repeating = {NotifType.touch: 'touch', NotifType.location: 'location', NotifType.locate: 'location'};
    final seen = <String>{};
    return [
      for (final n in items)
        if (!repeating.containsKey(n.type) || seen.add('${n.fromUserId}:${repeating[n.type]}')) n,
    ];
  }

  List<NotificationItem> _saved(String coupleId) => _collapseRepeats([
        for (final m in local.all(coupleId)) NotificationModel.fromMap(m),
      ]);

  @override
  Future<List<NotificationItem>> getNotifications(String coupleId) async {
    await collect();
    return _saved(coupleId);
  }

  Future<String?> _detail(Map<String, dynamic> row) async {
    final sealed = row['detail_enc'] as String?;
    if (!ContentCipher.isEncrypted(sealed)) return null;
    try {
      return await cipher.openText(sealed!, coupleId: row['couple_id'] as String, table: 'notifications', rowId: row['id'] as String, field: 'detail');
    } catch (e) {
      debugPrint('Could not read a notification detail: ${e.runtimeType}');
      return null;
    }
  }

  /// One collection at a time, so the same row is not opened and saved twice.
  Future<void> _tail = Future.value();

  int _retries = 0;

  /// A phone woken by a tap can be asked before the session, network or couple key is ready; try again
  /// shortly (a few times) instead of leaving the list empty.
  void _retryLater() {
    if (_retries >= 3) return;
    _retries++;
    Timer(const Duration(seconds: 3), () => collect());
  }

  @override
  Future<void> collect() {
    final run = _tail.then((_) async {
      try {
        final rows = await client
            .from('notifications')
            .select()
            .neq('from_user_id', _me ?? '')
            .order('created_at', ascending: false)
            .limit(50);
        final deferred = await _store(rows);
        if (deferred) { _retryLater(); } else { _retries = 0; }
      } catch (e) {
        debugPrint('Could not collect notifications: ${e.runtimeType}');
        _retryLater();
      }
    });
    _tail = run;
    return run;
  }

  /// Saves rows on this phone, then deletes them from the server. True when some rows were left because the
  /// couple key is not ready yet.
  Future<bool> _store(List<Map<String, dynamic>> rows) async {
    final mine = _me;
    final ack = <String>[];
    final fresh = <Map<String, dynamic>>[];
    var deferred = false;
    for (final row in rows) {
      if (row['from_user_id'] == mine) continue;
      final id = row['id'] as String;
      if (local.has(id)) { ack.add(id); continue; } // saved before, the delete did not get through
      String? detail;
      if (ContentCipher.isEncrypted(row['detail_enc'] as String?)) {
        // No couple key here yet: leave it on the server and try again later. With the key, a detail that
        // will not open shows the fixed sentence instead.
        if (!await cipher.isReady(row['couple_id'] as String)) { deferred = true; continue; }
        detail = await _detail(row);
      }
      fresh.add(NotificationModel.toMap(NotificationModel.fromRow(row, detail: detail)));
      ack.add(id);
    }
    if (fresh.isNotEmpty) {
      await local.putAll(fresh);
      await _prune(fresh.first['couple'] as String);
    }
    if (ack.isEmpty) return deferred;
    try {
      await client.rpc('ack_notifications', params: {'p_ids': ack});
    } catch (e) {
      debugPrint('Could not clear collected notifications: ${e.runtimeType}'); // saved here; asked again next time
    }
    return deferred;
  }

  /// Drops what the list no longer shows (older repeats) and anything past the cap.
  Future<void> _prune(String coupleId) async {
    final all  = local.all(coupleId).map(NotificationModel.fromMap).toList();
    final kept = _collapseRepeats(all).take(NotificationLocalSource.maxItems).map((n) => n.id).toSet();
    final drop = [for (final n in all) if (!kept.contains(n.id)) n.id];
    if (drop.isNotEmpty) await local.delete(drop);
  }

  @override
  Stream<List<NotificationItem>> watchNotifications(String coupleId) {
    final controller = StreamController<List<NotificationItem>>();
    StreamSubscription<void>? localSub;
    StreamSubscription<List<Map<String, dynamic>>>? serverSub;
    controller.onListen = () {
      localSub = local.changes.listen((_) => controller.add(_saved(coupleId)));
      controller.add(_saved(coupleId));
      // New rows arrive here while the screen is open; they are saved, which updates the list above.
      serverSub = client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('couple_id', coupleId)
          .listen((_) => collect(), onError: (Object _) {}); // dropped Realtime connection: keep the screen alive
      collect();
    };
    controller.onCancel = () async {
      await localSub?.cancel();
      await serverSub?.cancel();
    };
    return controller.stream;
  }

  @override
  Future<void> markRead(String coupleId, String notificationId) => local.markRead(notificationId);

  @override
  Future<void> markAllRead(String coupleId) => local.markAllRead(coupleId);

  @override
  Stream<int> watchUnreadCount(String coupleId) async* {
    int unread() => _saved(coupleId).where((n) => !n.isRead).length;
    yield unread();
    yield* local.changes.map((_) => unread());
  }

  @override
  Future<void> reset() => local.clear();

  /// What the stored (and pushed) text says in place of the sender's name: the server and the lock screen
  /// never get the name from here. The named sentence is sealed into `detail_enc` and shown inside the app.
  static const anonymousSender = 'Your partner';

  @override
  Future<void> notifyPartner({
    required String coupleId,
    required String fromUserId,
    required NotifType type,
    required String Function(String senderName) body,
    String Function(String senderName)? detail,
  }) async {
    try {
      final name = await _senderName(fromUserId);
      final id = _uuid.v4(); // chosen here: the encrypted detail is bound to this row
      // Every notification carries its full sentence (with the name, and any typed words) sealed; when the
      // caller gave no separate detail, the named version of the body is that sentence.
      final named = detail != null ? detail(name) : body(name);
      String? sealed;
      try {
        sealed = await cipher.sealText(named, coupleId: coupleId, table: 'notifications', rowId: id, field: 'detail');
      } catch (_) {
        // No couple key yet: the partner gets the nameless sentence only, never the detail in the clear.
      }
      // The recipient is the sender's partner; the push is sent by an Edge Function.
      await client.from('notifications').insert({
        'id':           id,
        'couple_id':    coupleId,
        'from_user_id': fromUserId,
        'type':         type.name,
        'body_text':    body(anonymousSender),
        if (sealed != null) 'detail_enc': sealed,
      });
    } catch (_) {}
  }

  /// Turns pushes on or off for THIS device only; the account's other devices
  /// are not affected.
  @override
  Future<void> toggleFcm({required bool enabled, required String uid}) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (enabled) {
      if (token != null) await client.rpc('register_device_token', params: {'p_token': token});
    } else {
      // Remove the server row first (it needs the token), then the token itself.
      if (token != null) await client.from('device_tokens').delete().eq('fcm_token', token);
      await FirebaseMessaging.instance.deleteToken();
    }
  }

  /// Which alerts arrive quietly: one choice per person, kept on their profile
  /// so every device of theirs follows it.
  @override
  Future<Set<String>> getSilentTypes() async {
    final uid = _me;
    if (uid == null) return NotifType.defaultSilent;
    final row = await client.from('profiles').select('silent_types').eq('id', uid).maybeSingle();
    final types = row?['silent_types'];
    return types is List ? types.cast<String>().toSet() : NotifType.defaultSilent;
  }

  @override
  Future<void> setSilentTypes(Set<String> types) async {
    final uid = _me;
    if (uid == null) return;
    await client.from('profiles').update({'silent_types': types.toList()}).eq('id', uid);
  }
}
