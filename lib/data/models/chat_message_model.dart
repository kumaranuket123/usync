import '../../domain/entities/chat_message.dart';
import '../datasources/remote/chat_media_source.dart';

/// How a [ChatMessage] is kept on the phone (the local, encrypted chat box). Times are microseconds since
/// the epoch (UTC), so a message sorts by the same number it is keyed by.
class ChatMessageModel {
  const ChatMessageModel._();

  static Map<String, dynamic> toMap(ChatMessage m, {required bool mine, required bool hasMedia}) => {
        'id':   m.id,
        'cid':  m.coupleId,
        's':    m.senderId,
        'mine': mine,
        'k':    m.kind.name,
        'at':   m.createdAt.toUtc().microsecondsSinceEpoch,
        if (m.text != null) 't': m.text,
        if (m.durationMs != null) 'd': m.durationMs,
        if (m.reply != null) 'r': m.reply!.toJson(),
        'ttl':  m.ttlSeconds,
        if (m.seenAt != null) 'seen': m.seenAt!.toUtc().microsecondsSinceEpoch,
        if (m.deliveredAt != null) 'del': m.deliveredAt!.toUtc().microsecondsSinceEpoch,
        if (m.expiresAt != null) 'exp': m.expiresAt!.toUtc().microsecondsSinceEpoch,
        'p':    m.pending,
        'm':    hasMedia,
      };

  static ChatMessage fromMap(Map<dynamic, dynamic> map) {
    DateTime? time(String key) => map[key] == null ? null : DateTime.fromMicrosecondsSinceEpoch(map[key] as int, isUtc: true);
    final id = map['id'] as String;
    final coupleId = map['cid'] as String;
    return ChatMessage(
      id:          id,
      coupleId:    coupleId,
      senderId:    map['s'] as String?,
      kind:        ChatKind.fromKey(map['k'] as String),
      createdAt:   time('at')!,
      expiresAt:   time('exp'),
      text:        map['t'] as String?,
      durationMs:  map['d'] as int?,
      mediaPath:   map['m'] == true ? ChatMediaSource.pathFor(coupleId, id) : null,
      seenAt:      time('seen'),
      deliveredAt: time('del'),
      pending:     map['p'] == true,
      ttlSeconds:  map['ttl'] as int? ?? 0,
      reply:       ChatReply.fromJson(map['r']),
    );
  }
}
