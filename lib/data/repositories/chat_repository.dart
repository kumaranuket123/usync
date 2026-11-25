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
import '../datasources/local/prefs_source.dart';
import '../datasources/remote/chat_media_source.dart';
import '../datasources/remote/couple_channel_source.dart';

class ChatRepository implements IChatRepository {
  ChatRepository({
    required this.client,
    required this.media,
    required this.notifications,
    required this.outbox,
    required this.cipher,
    required this.channelSource,
    required this.prefs,
  }) {
    outbox.register(_outboxType, _deliver);
  }

  static const _outboxType = 'chat_message';
  static const _table      = 'chat_messages';
  /// The newest messages loaded at once.
  static const _limit      = 200;
  /// What a user announces on Presence while looking at the chat.
  static const screen      = 'chat';

  final SupabaseClient          client;
  final ChatMediaSource         media;
  final INotificationRepository notifications;
  final OutboxService           outbox;
  final ContentCipher           cipher;
  final CoupleChannelSource     channelSource;
  final PrefsSource             prefs;
  final _uuid = const Uuid();

  // ── Reading ──────────────────────────────────────────────────────────────

  /// Opened rows by id, so a stream event does not decrypt every message again. Keyed by the sealed
  /// text too, so a changed row is opened again.
  final _opened = <String, ({String enc, Map<String, dynamic>? content})>{};

  @override
  Stream<List<ChatMessage>> watchMessages(String coupleId) => client
      .from(_table)
      .stream(primaryKey: ['id'])
      .eq('couple_id', coupleId)
      .order('created_at', ascending: false)
      .limit(_limit)
      .asyncMap((rows) async => [for (final row in rows.reversed) await _toMessage(row)])
      .handleError((Object _) {}); // dropped Realtime connection: keep the screen alive

  Future<ChatMessage> _toMessage(Map<String, dynamic> row) async {
    final id  = row['id'] as String;
    final enc = row['enc'] as String;
    final coupleId = row['couple_id'] as String;
    var cached = _opened[id];
    if (cached == null || cached.enc != enc) {
      Map<String, dynamic>? content;
      try {
        content = await cipher.openJson(enc, coupleId: coupleId, table: _table, rowId: id);
      } catch (e) {
        debugPrint('Could not read a chat message: ${e.runtimeType}'); // shown as locked, not dropped
      }
      cached = (enc: enc, content: content);
      _opened[id] = cached;
    }
    final c = cached.content;
    return ChatMessage(
      id:         id,
      coupleId:   coupleId,
      senderId:   row['sender_id'] as String?,
      kind:       ChatKind.fromKey(row['kind'] as String),
      createdAt:  DateTime.parse(row['created_at'] as String),
      expiresAt:  DateTime.parse(row['expires_at'] as String),
      seenAt:     row['seen_at'] == null ? null : DateTime.parse(row['seen_at'] as String),
      mediaPath:  row['media_path'] as String?,
      text:       c?['t'] as String?,
      durationMs: c?['d'] as int?,
      reply:      ChatReply.fromJson(c?['r']),
      locked:     c == null,
      ttlSeconds: row['ttl_seconds'] as int? ?? ChatTimer.defaultTimer.seconds,
    );
  }

  /// The partner's messages in [rows] that have not been seen, still exist and were not deleted ([gone]).
  @visibleForTesting
  static int countUnread(List<Map<String, dynamic>> rows, {required String userId, required Set<String> gone, required DateTime now}) =>
      rows.where((r) =>
          r['sender_id'] != userId &&
          r['seen_at'] == null &&
          !gone.contains(r['id']) &&
          DateTime.parse(r['expires_at'] as String).isAfter(now)).length;

  @override
  Stream<int> watchUnreadCount({required String coupleId, required String userId}) {
    late final StreamController<int> out;
    final subs = <StreamSubscription<Object?>>[];
    var rows = const <Map<String, dynamic>>[];
    // Deleted by the partner (the table stream does not report deletions).
    final gone = <String>{};

    void publish() {
      if (out.isClosed) return;
      out.add(countUnread(rows, userId: userId, gone: gone, now: DateTime.now()));
    }

    out = StreamController<int>(
      onListen: () {
        final channel = channelSource.open(coupleId);
        subs.add(client.from(_table).stream(primaryKey: ['id']).eq('couple_id', coupleId).listen(
          (r) { rows = r; publish(); },
          onError: (_) {}, // dropped Realtime connection: keep the last count
        ));
        subs.add(channel.on(CoupleChannel.chatDelete).listen((m) {
          final ids = m['ids'];
          if (ids is List) gone.addAll(ids.whereType<String>());
          publish();
        }));
        subs.add(channel.on(CoupleChannel.chatClear).listen((_) {
          gone.addAll(rows.map((r) => r['id'] as String));
          publish();
        }));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
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
  /// second message. Fails early, before queueing, when this phone has no couple key.
  Future<bool> _submit(String coupleId, String userId, ChatKind kind, {String? text, Uint8List? bytes, int? durationMs, ChatReply? replyTo}) async {
    if (!await cipher.isReady(coupleId)) throw const EncryptionNotReady();
    return outbox.submit(_outboxType, {
      'id':         _uuid.v4(),
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
    await client.rpc('send_chat_message', params: {
      'p_id':         id,
      'p_couple':     coupleId,
      'p_kind':       kind.name,
      'p_enc':        enc,
      'p_media_path': path,
      'p_ttl':        ChatTimer.fromSeconds(p['ttl'] as int?).seconds,
    });
    unawaited(_notify(coupleId, userId));
  }

  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  /// A push for a partner who is not looking at the chat, at most one a minute, with fixed text (no
  /// name, no content).
  Future<void> _notify(String coupleId, String userId) async {
    try {
      final now = DateTime.now();
      if (now.difference(_lastPush) < const Duration(minutes: 1)) return;
      final channel = channelSource.open(coupleId);
      await channel.whenReady(const Duration(seconds: 3));
      if (channel.presenceSynced) {
        final partnerHere = channel.presenceScreens.entries.any((e) => e.key != userId && e.value == screen);
        if (partnerHere) return;
      }
      _lastPush = now;
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

  // ── Seen, media, presence ────────────────────────────────────────────────

  @override
  Future<void> markSeen(List<String> ids) async {
    if (ids.isEmpty) return;
    await client.rpc('mark_chat_seen', params: {'p_ids': ids});
  }

  @override
  Future<void> deleteMessage({required String coupleId, required String userId, required String id}) async {
    await client.rpc('delete_chat_message', params: {'p_id': id});
    _forget(id);
    // The table stream does not report deletions, so tell the partner's phone directly. A phone that
    // misses this (offline) simply does not get the message when it next loads the chat.
    try {
      await channelSource.open(coupleId).send(CoupleChannel.chatDelete, {'ids': [id], 'from': userId});
    } catch (_) {}
  }

  @override
  Stream<String> watchDeleted(String coupleId) => channelSource
      .open(coupleId)
      .on(CoupleChannel.chatDelete)
      .expand((m) {
        final ids = m['ids'];
        return ids is List ? ids.whereType<String>() : const <String>[];
      })
      .map((id) {
        _forget(id);
        return id;
      });

  @override
  Future<void> clearChat({required String coupleId, required String userId}) async {
    await client.rpc('clear_chat', params: {'p_couple': coupleId});
    _forgetAll();
    try {
      await channelSource.open(coupleId).send(CoupleChannel.chatClear, {'from': userId});
    } catch (_) {}
  }

  @override
  Stream<void> watchCleared(String coupleId) => channelSource.open(coupleId).on(CoupleChannel.chatClear).map((_) {
        _forgetAll();
      });

  void _forgetAll() {
    _opened.clear();
    _media.clear();
  }

  /// Drops what is kept in memory about a message that no longer exists.
  void _forget(String id) {
    _opened.remove(id);
    _media.remove(id);
  }

  /// Decrypted media kept in memory only (never written to the phone). Small, so a photo or voice note
  /// is not downloaded again each time it scrolls into view.
  static const _mediaCacheSize = 12;
  final _media   = <String, Uint8List>{};
  final _loading = <String, Future<Uint8List?>>{};

  @override
  Future<Uint8List?> loadMedia(ChatMessage message) {
    final path = message.mediaPath;
    if (path == null || message.locked) return Future.value(null);
    final hit = _media.remove(message.id);
    if (hit != null) {
      _media[message.id] = hit; // most recently used last
      return Future.value(hit);
    }
    return _loading[message.id] ??= () async {
      try {
        final sealed = await media.download(path);
        final bytes = await cipher.openBytes(sealed, coupleId: message.coupleId, table: _table, rowId: message.id, field: 'media');
        _media[message.id] = bytes;
        while (_media.length > _mediaCacheSize) {
          _media.remove(_media.keys.first);
        }
        return bytes;
      } catch (e) {
        debugPrint('Could not load chat media: ${e.runtimeType}');
        return null;
      } finally {
        _loading.remove(message.id);
      }
    }();
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
