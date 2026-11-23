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
      locked:     c == null,
    );
  }

  // ── Sending ──────────────────────────────────────────────────────────────

  @override
  ChatTimer get timer => ChatTimer.fromSeconds(prefs.chatTimerSeconds);

  @override
  Future<void> setTimer(ChatTimer timer) => prefs.setChatTimerSeconds(timer.seconds);

  @override
  Future<bool> sendText({required String coupleId, required String userId, required String text}) =>
      _submit(coupleId, userId, ChatKind.text, text: text);

  @override
  Future<bool> sendImage({required String coupleId, required String userId, required Uint8List bytes}) =>
      _submit(coupleId, userId, ChatKind.image, bytes: bytes);

  @override
  Future<bool> sendVoice({required String coupleId, required String userId, required Uint8List bytes, required int durationMs}) =>
      _submit(coupleId, userId, ChatKind.voice, bytes: bytes, durationMs: durationMs);

  /// The message id is chosen here, not when sending, so a retry after a lost connection cannot add a
  /// second message. Fails early, before queueing, when this phone has no couple key.
  Future<bool> _submit(String coupleId, String userId, ChatKind kind, {String? text, Uint8List? bytes, int? durationMs}) async {
    if (!await cipher.isReady(coupleId)) throw const EncryptionNotReady();
    return outbox.submit(_outboxType, {
      'id':         _uuid.v4(),
      'coupleId':   coupleId,
      'userId':     userId,
      'kind':       kind.name,
      'text':       text,
      'bytes':      bytes,
      'durationMs': durationMs,
      // Fixed now, so a message waiting for a connection keeps the timer it was written with.
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
      {'t': p['text'], 'd': p['durationMs']}..removeWhere((_, v) => v == null),
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
