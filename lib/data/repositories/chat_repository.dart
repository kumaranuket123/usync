import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/crypto/content_cipher.dart';
import '../../core/services/outbox_service.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_chat_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/local/chat_local_source.dart';
import '../datasources/local/prefs_source.dart';
import '../datasources/remote/chat_media_source.dart';
import '../datasources/remote/couple_channel_source.dart';
import '../models/chat_message_model.dart';

/// The history is on this phone ([local]); the server (`chat_messages`) is a mailbox that holds a message
/// only until the partner's phone has saved it and said so (`ack_chat_messages`).
class ChatRepository implements IChatRepository {
  ChatRepository({
    required this.client,
    required this.media,
    required this.notifications,
    required this.outbox,
    required this.cipher,
    required this.channelSource,
    required this.prefs,
    required this.local,
  }) {
    outbox.register(_outboxType, _deliver);
    outbox.register(_controlType, _deliverControl);
  }

  static const _outboxType  = 'chat_message';
  static const _controlType = 'chat_control';
  static const _table       = 'chat_messages';
  /// How many messages one page of the chat shows.
  static const pageSize     = 30;
  /// What a user announces on Presence while looking at the chat.
  static const screen       = 'chat';

  final SupabaseClient          client;
  final ChatMediaSource         media;
  final INotificationRepository notifications;
  final OutboxService           outbox;
  final ContentCipher           cipher;
  final CoupleChannelSource     channelSource;
  final PrefsSource             prefs;
  final ChatLocalSource         local;
  final _uuid = const Uuid();

  static int _micros(DateTime t) => t.toUtc().microsecondsSinceEpoch;

  // ── Collecting what the partner sent ─────────────────────────────────────

  String _me = '', _couple = '';
  String? _inboxKey;
  StreamSubscription<List<Map<String, dynamic>>>? _inboxSub;
  List<Map<String, dynamic>>? _queued;
  bool _draining = false;
  /// The first snapshot on a fresh history also brings in the user's own messages the server still holds.
  bool _importOwn = false;

  /// Bumped by [reset]: a pass that started before it must not write anything.
  int _generation = 0;
  Future<void>? _starting;

  @override
  Future<void> startInbox({required String coupleId, required String userId}) {
    // Not signed in / no couple known yet (a phone woken by a notification): nothing to collect, and the
    // history must be left alone.
    if (coupleId.isEmpty || userId.isEmpty) return Future.value();
    final key = '$userId:$coupleId';
    if (_inboxKey == key && local.owner == key) return _starting ?? Future.value();
    _inboxKey = key;
    return _starting = _start(key, coupleId, userId);
  }

  Future<void> _start(String key, String coupleId, String userId) async {
    final generation = _generation;
    _me = userId;
    _couple = coupleId;
    await _inboxSub?.cancel();
    // Another account's history never stays on this phone.
    _importOwn = await local.claim(key);
    if (generation != _generation) return; // signed out while starting
    _inboxSub = client.from(_table).stream(primaryKey: ['id']).eq('couple_id', coupleId).listen(
      (rows) {
        _queued = rows;
        unawaited(_drain());
      },
      onError: (_) {}, // dropped Realtime connection: it reconnects, and the next snapshot has everything
    );
  }

  /// Runs one collecting pass over [rows] as if they had come from the server (tests only).
  @visibleForTesting
  Future<void> collectForTest(List<Map<String, dynamic>> rows, {required String coupleId, required String userId, bool importOwn = false}) {
    _couple = coupleId;
    _me = userId;
    _importOwn = importOwn;
    return _collect(rows);
  }

  /// Sign-out or the couple ended: stop collecting, forget what this session knew, and make a pass that is
  /// still running write nothing. (The history itself is wiped by [ChatLocalSource.reset].)
  @override
  Future<void> reset() async {
    _generation++;
    _inboxKey = null;
    _starting = null;
    _queued = null;
    _me = _couple = '';
    _importOwn = false;
    _window = pageSize;
    _hasOlder = false;
    _media.clear();
    final sub = _inboxSub;
    _inboxSub = null;
    await sub?.cancel();
    await local.reset();
  }

  /// One pass at a time; a newer snapshot replaces one that is still waiting.
  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queued != null) {
        final rows = _queued!;
        _queued = null;
        await _collect(rows);
      }
    } catch (e) {
      debugPrint('Could not collect chat messages: ${e.runtimeType}');
    } finally {
      _draining = false;
    }
  }

  Future<void> _collect(List<Map<String, dynamic>> rows) async {
    final generation = _generation;
    final importOwn = _importOwn;
    _importOwn = false;
    DateTime at(Map<String, dynamic> r) => DateTime.parse(r['created_at'] as String);
    final ordered = [...rows]..sort((a, b) => at(a).compareTo(at(b)));
    final collected = <String>[], delivered = <String>[], lasting = <String>[];
    var failed = false;
    for (final row in ordered) {
      if (generation != _generation) return;
      final id = row['id'] as String;
      try {
        if (row['sender_id'] == _me) {
          if (importOwn && row['kind'] != 'control' && !local.knows(id)) await _save(row, mine: true);
          continue;
        }
        if (row['kind'] == 'control') {
          await _apply(row);
          // A delete or clear must still be there next time if a message it refers to could not be saved
          // in this pass (it would otherwise survive it); applying it again changes nothing.
          (await _isReceipt(row) ? collected : lasting).add(id);
        } else if (local.knows(id)) {
          collected.add(id); // saved earlier (and maybe deleted since); the delete did not get through
        } else if (await _save(row, mine: false)) {
          collected.add(id);
          delivered.add(id);
        } else {
          failed = true;
        }
      } catch (e) {
        failed = true;
        debugPrint('Could not collect a chat message: ${e.runtimeType}'); // it stays on the server; next time
      }
    }
    if (generation != _generation) return;
    if (!failed) collected.addAll(lasting);
    // Saved first, collected second: a crash in between only brings the message again, and it is skipped.
    for (var i = 0; i < collected.length; i += 500) {
      try {
        await client.rpc('ack_chat_messages', params: {'p_ids': collected.sublist(i, i + 500 > collected.length ? collected.length : i + 500)});
      } catch (_) {}
    }
    if (delivered.isNotEmpty) await _sendControl({'c': 'receipt', 'k': 'delivered', 'ids': delivered}).catchError((_) => false);
  }

  /// Opens a message row and keeps it on this phone, with its photo or voice note. False when it cannot be
  /// opened yet (no couple key, file not there): it then stays on the server.
  Future<bool> _save(Map<String, dynamic> row, {required bool mine}) async {
    final id = row['id'] as String;
    final Map<String, dynamic> content;
    try {
      content = await cipher.openJson(row['enc'] as String, coupleId: _couple, table: _table, rowId: id);
    } catch (_) {
      return false;
    }
    final kind = ChatKind.fromKey(row['kind'] as String);
    Uint8List? bytes;
    if (kind != ChatKind.text) {
      final path = row['media_path'] as String?;
      if (path == null) return false;
      try {
        bytes = await cipher.openBytes(await media.download(path), coupleId: _couple, table: _table, rowId: id, field: 'media');
      } catch (_) {
        return false;
      }
    }
    final seenAt = row['seen_at'] == null ? null : DateTime.parse(row['seen_at'] as String);
    final message = ChatMessage(
      id:          id,
      coupleId:    _couple,
      senderId:    row['sender_id'] as String?,
      kind:        kind,
      createdAt:   DateTime.parse(row['created_at'] as String),
      // Rows from before the mailbox change may already be read: their timer is as the old server set it.
      expiresAt:   seenAt == null || row['expires_at'] == null ? null : DateTime.parse(row['expires_at'] as String),
      text:        content['t'] as String?,
      durationMs:  content['d'] as int?,
      seenAt:      seenAt,
      deliveredAt: mine && seenAt != null ? seenAt : null,
      ttlSeconds:  row['ttl_seconds'] as int? ?? 0,
      reply:       ChatReply.fromJson(content['r']),
    );
    await local.put(ChatMessageModel.toMap(message, mine: mine, hasMedia: bytes != null), media: bytes);
    return true;
  }

  Future<bool> _isReceipt(Map<String, dynamic> row) async {
    final content = await cipher.openJson(row['enc'] as String, coupleId: _couple, table: _table, rowId: row['id'] as String);
    return content['c'] == 'receipt';
  }

  /// Carries out a control envelope from the partner.
  Future<void> _apply(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final content = await cipher.openJson(row['enc'] as String, coupleId: _couple, table: _table, rowId: id);
    final ids = [for (final x in (content['ids'] as List? ?? const [])) x as String];
    switch (content['c']) {
      case 'receipt':
        final read = content['k'] == 'read';
        final now = DateTime.now().toUtc();
        for (final messageId in ids) {
          await local.update(messageId, (m) {
            if (m['mine'] != true) return m;
            final ttl = m['ttl'] as int? ?? 0;
            return {
              ...m,
              'p': false,
              'del': m['del'] ?? _micros(now),
              if (read && m['seen'] == null) ...{
                'seen': _micros(now),
                if (ttl > 0) 'exp': _micros(now.add(Duration(seconds: ttl))),
              },
            };
          });
        }
      case 'delete':
        // The partner can remove only what the partner wrote.
        final mine = <String>[];
        for (final messageId in ids) {
          final m = await local.get(messageId);
          if (m != null && m['s'] == row['sender_id']) mine.add(messageId);
        }
        await local.delete(mine);
        // Not here yet (still on its way): remember the delete, so it is not saved when it does arrive.
        await local.forget([for (final id in ids) if (!local.has(id)) id]);
      case 'clear':
        await local.delete(local.idsAtOrBefore(_micros(DateTime.parse(row['created_at'] as String))));
    }
  }

  // ── Reading ──────────────────────────────────────────────────────────────

  int _window = pageSize;
  bool _hasOlder = false;
  Future<void> Function()? _refresh;

  @override
  bool get hasOlder => _hasOlder;

  @override
  Stream<List<ChatMessage>> watchMessages(String coupleId) {
    late final StreamController<List<ChatMessage>> out;
    StreamSubscription<void>? sub;
    var busy = false, again = false;

    Future<void> emit() async {
      if (busy) {
        again = true;
        return;
      }
      busy = true;
      try {
        do {
          again = false;
          final rows = await local.page(limit: _window);
          _hasOlder = rows.isNotEmpty && local.hasOlderThan(rows.first['at'] as int);
          if (!out.isClosed) out.add([for (final r in rows) ChatMessageModel.fromMap(r)]);
        } while (again);
      } catch (e) {
        debugPrint('Could not read the chat: ${e.runtimeType}');
      } finally {
        busy = false;
      }
    }

    out = StreamController<List<ChatMessage>>(
      onListen: () {
        _window = pageSize;
        _refresh = emit;
        sub = local.changes.listen((_) => unawaited(emit()));
        unawaited(emit());
      },
      onCancel: () async {
        _refresh = null;
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<bool> loadOlder() async {
    if (!_hasOlder) return false;
    _window += pageSize;
    await _refresh?.call();
    return _hasOlder;
  }

  @override
  Future<void> purgeExpired() => local.delete(local.expiredIds(DateTime.now()));

  @override
  Stream<int> watchUnreadCount({required String coupleId, required String userId}) {
    startInbox(coupleId: coupleId, userId: userId).catchError((Object e) {
      debugPrint('Could not start collecting chat messages: ${e.runtimeType}');
    });
    late final StreamController<int> out;
    StreamSubscription<void>? sub;
    int? last;
    void publish() {
      final n = local.unreadCount;
      if (n != last && !out.isClosed) out.add(last = n);
    }

    out = StreamController<int>(
      onListen: () {
        publish();
        sub = local.changes.listen((_) => publish());
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  // ── Sending ──────────────────────────────────────────────────────────────

  /// The last timer this phone knew, so the chat can show one before the server has answered.
  late ChatTimer _timer = ChatTimer.fromSeconds(prefs.chatTimerSeconds);

  @override
  ChatTimer get timer => _timer;

  @override
  Future<void> setTimer({required String coupleId, required ChatTimer timer}) async {
    await client.rpc('set_chat_timer', params: {'p_couple': coupleId, 'p_seconds': timer.seconds});
    _remember(timer);
  }

  void _remember(ChatTimer timer) {
    _timer = timer;
    prefs.setChatTimerSeconds(timer.seconds).ignore();
  }

  @override
  Stream<ChatTimer> watchTimer(String coupleId) => client
      .from('couples')
      .stream(primaryKey: ['id'])
      .eq('id', coupleId)
      .where((rows) => rows.isNotEmpty)
      .map((rows) => ChatTimer.fromSeconds(rows.first['chat_ttl_seconds'] as int?))
      .map((t) {
        _remember(t);
        return t;
      })
      .handleError((Object _) {}); // dropped Realtime connection: keep the last known timer

  @override
  Future<bool> sendText({required String coupleId, required String userId, required String text, ChatReply? replyTo}) =>
      _submit(coupleId, userId, ChatKind.text, text: text, replyTo: replyTo);

  @override
  Future<bool> sendImage({required String coupleId, required String userId, required Uint8List bytes, ChatReply? replyTo}) =>
      _submit(coupleId, userId, ChatKind.image, bytes: bytes, replyTo: replyTo);

  @override
  Future<bool> sendVoice({required String coupleId, required String userId, required Uint8List bytes, required int durationMs, ChatReply? replyTo}) =>
      _submit(coupleId, userId, ChatKind.voice, bytes: bytes, durationMs: durationMs, replyTo: replyTo);

  /// The message id is chosen here, not when sending, so a retry after a lost connection cannot add a
  /// second message. Fails early, before anything is kept or queued, when this phone has no couple key.
  /// The message is on the screen at once (still "pending"); the server's time replaces the phone's when it arrives.
  Future<bool> _submit(String coupleId, String userId, ChatKind kind, {String? text, Uint8List? bytes, int? durationMs, ChatReply? replyTo}) async {
    if (!await cipher.isReady(coupleId)) throw const EncryptionNotReady();
    final id = _uuid.v4();
    final message = ChatMessage(
      id: id, coupleId: coupleId, senderId: userId, kind: kind, createdAt: DateTime.now().toUtc(),
      text: text, durationMs: durationMs, pending: true, ttlSeconds: timer.seconds, reply: replyTo,
    );
    await local.put(ChatMessageModel.toMap(message, mine: true, hasMedia: bytes != null), media: bytes);
    try {
      return await outbox.submit(_outboxType, {
        'id':         id,
        'coupleId':   coupleId,
        'userId':     userId,
        'kind':       kind.name,
        'text':       text,
        'bytes':      bytes,
        'durationMs': durationMs,
        'reply':      replyTo?.toJson(),
        // Only a hint: the server stamps the message with the couple's timer when it receives it.
        'ttl':        timer.seconds,
      });
    } catch (e) {
      await local.delete([id]); // refused: it must not sit on the screen looking sent
      rethrow;
    }
  }

  Future<void> _deliver(Map<String, dynamic> p) async {
    final coupleId = p['coupleId'] as String;
    final userId   = p['userId'] as String;
    final id       = p['id'] as String;
    final kind     = ChatKind.fromKey(p['kind'] as String);

    // Everything is sealed before it leaves the phone; without the couple key this throws and nothing is sent.
    final enc = await cipher.sealJson(
      {'t': p['text'], 'd': p['durationMs'], 'r': p['reply']}..removeWhere((_, v) => v == null),
      coupleId: coupleId, table: _table, rowId: id,
    );
    String? path;
    if (kind != ChatKind.text) {
      final sealed = await cipher.sealBytes((p['bytes'] as List).cast<int>(), coupleId: coupleId, table: _table, rowId: id, field: 'media');
      path = ChatMediaSource.pathFor(coupleId, id);
      await media.upload(path, sealed);
    }
    final sentAt = await client.rpc('send_chat_message', params: {
      'p_id':         id,
      'p_couple':     coupleId,
      'p_kind':       kind.name,
      'p_enc':        enc,
      'p_media_path': path,
      'p_ttl':        ChatTimer.fromSeconds(p['ttl'] as int?).seconds,
    });
    // Reached the server: no longer pending, and ordered by the server's time like the partner's messages.
    final at = DateTime.tryParse('$sentAt');
    await local.update(id, (m) => {...m, 'p': false, if (at != null) 'at': _micros(at)});
    unawaited(_notify(coupleId, userId));
  }

  /// Receipts, "delete for everyone" and "clear for both" go through the same mailbox, sealed like a
  /// message, and are queued when offline. No push.
  Future<bool> _sendControl(Map<String, dynamic> content, {String? coupleId}) => outbox.submit(_controlType, {
        'id':       _uuid.v4(),
        'coupleId': coupleId ?? _couple,
        'content':  content,
      });

  Future<void> _deliverControl(Map<String, dynamic> p) async {
    final id = p['id'] as String;
    final coupleId = p['coupleId'] as String;
    final enc = await cipher.sealJson(Map<String, dynamic>.from(p['content'] as Map), coupleId: coupleId, table: _table, rowId: id);
    await client.rpc('send_chat_message', params: {
      'p_id':         id,
      'p_couple':     coupleId,
      'p_kind':       'control',
      'p_enc':        enc,
      'p_media_path': null,
      'p_ttl':        0,
    });
  }

  /// A push for a partner who is not looking at the chat, one per message (each replaces the last one on the
  /// partner's phone and shows how many messages are waiting, see `send-push`), with fixed text (no name, no
  /// content).
  Future<void> _notify(String coupleId, String userId) async {
    try {
      final channel = channelSource.open(coupleId);
      await channel.whenReady(const Duration(seconds: 3));
      if (channel.presenceSynced) {
        final partnerHere = channel.presenceScreens.entries.any((e) => e.key != userId && e.value == screen);
        if (partnerHere) return;
      }
      await notifications.notifyPartner(
        coupleId:   coupleId,
        fromUserId: userId,
        type:       NotifType.chat,
        body:       (_) => 'New message 💬',
      );
    } catch (e) {
      debugPrint('Could not send the chat notification: ${e.runtimeType}');
    }
  }

  // ── Read, delete, media, presence ────────────────────────────────────────

  @override
  Future<void> markSeen(List<String> ids) async {
    final now = DateTime.now().toUtc();
    final read = <String>[];
    for (final id in ids) {
      await local.update(id, (m) {
        if (m['mine'] == true || m['seen'] != null) return m;
        read.add(id);
        final ttl = m['ttl'] as int? ?? 0;
        return {...m, 'seen': _micros(now), if (ttl > 0) 'exp': _micros(now.add(Duration(seconds: ttl)))};
      });
    }
    if (read.isNotEmpty) await _sendControl({'c': 'receipt', 'k': 'read', 'ids': read});
  }

  @override
  Future<void> deleteForMe(String id) => local.delete([id]);

  @override
  Future<void> deleteForEveryone({required String coupleId, required String userId, required String id}) async {
    await local.delete([id]);
    // Not collected yet: remove it from the mailbox so the partner never gets it.
    try {
      await client.rpc('delete_chat_message', params: {'p_id': id});
    } catch (_) {}
    await _sendControl({'c': 'delete', 'ids': [id]}, coupleId: coupleId);
  }

  @override
  Future<void> clearChat({required String coupleId, required String userId, required bool forEveryone}) async {
    await local.clear();
    _media.clear();
    if (!forEveryone) return;
    try {
      await client.rpc('clear_chat', params: {'p_couple': coupleId});
    } catch (_) {}
    await _sendControl({'c': 'clear'}, coupleId: coupleId);
  }

  /// Decrypted media kept in memory for a moment, so a photo or voice note is not read from the box again
  /// each time it scrolls into view.
  static const _mediaCacheSize = 30;
  final _media = <String, Uint8List>{};

  @override
  Future<Uint8List?> loadMedia(ChatMessage message) async {
    if (message.mediaPath == null) return null;
    final hit = _media.remove(message.id);
    if (hit != null) {
      _media[message.id] = hit; // most recently used last
      return hit;
    }
    final bytes = await local.mediaBytes(message.id);
    if (bytes == null) return null;
    _media[message.id] = bytes;
    while (_media.length > _mediaCacheSize) {
      _media.remove(_media.keys.first);
    }
    return bytes;
  }

  @override
  Future<void> enterChat({required String coupleId, required String userId}) =>
      channelSource.open(coupleId).track({
        'user_id':    userId,
        'screen':     screen,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

  @override
  Future<void> leaveChat({required String coupleId, required String userId}) =>
      channelSource.open(coupleId).track({
        'user_id':    userId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
}
