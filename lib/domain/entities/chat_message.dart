import 'package:equatable/equatable.dart';

enum ChatKind {
  text,
  image,
  voice;

  static ChatKind fromKey(String key) => values.firstWhere((k) => k.name == key, orElse: () => ChatKind.text);
}

/// How long a message lives on the phones once it has been read; [off] keeps it until someone deletes it.
/// One setting for the couple, stored with each message (the server accepts only these values).
enum ChatTimer {
  off(0, 'Off', 'Off'),
  tenSeconds(10, '10 seconds', '10 sec'),
  oneMinute(60, '1 minute', '1 min'),
  fiveMinutes(300, '5 minutes', '5 min'),
  oneHour(3600, '1 hour', '1 hour'),
  oneDay(86400, '1 day', '1 day');

  const ChatTimer(this.seconds, this.label, this.shortLabel);

  final int    seconds;
  final String label;
  final String shortLabel;

  Duration get duration => Duration(seconds: seconds);

  bool get isOff => seconds == 0;

  /// What a new chat starts with, and what an unknown stored value falls back to.
  static const defaultTimer = ChatTimer.off;

  static ChatTimer fromSeconds(int? seconds) =>
      values.firstWhere((t) => t.seconds == seconds, orElse: () => defaultTimer);
}

/// The message a reply answers: a short copy kept inside the (encrypted) reply, so it still shows after
/// the original has vanished.
class ChatReply extends Equatable {
  const ChatReply({required this.messageId, required this.senderId, required this.kind, this.text});

  /// Longest quoted text.
  static const maxText = 120;

  final String    messageId;
  final String?   senderId;
  final ChatKind  kind;
  /// The quoted text (text messages only; photos and voice notes show a label instead).
  final String?   text;

  factory ChatReply.of(ChatMessage m) => ChatReply(
        messageId: m.id,
        senderId:  m.senderId,
        kind:      m.kind,
        text:      m.kind == ChatKind.text && m.text != null
            ? (m.text!.length > maxText ? m.text!.substring(0, maxText) : m.text)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': messageId,
        if (senderId != null) 's': senderId,
        'k': kind.name,
        if (text != null) 't': text,
      };

  static ChatReply? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    return ChatReply(
      messageId: id,
      senderId:  json['s'] as String?,
      kind:      ChatKind.fromKey(json['k'] as String? ?? 'text'),
      text:      json['t'] as String?,
    );
  }

  @override
  List<Object?> get props => [messageId, senderId, kind, text];
}

/// One message of the private chat, as kept on this phone. With a [ChatTimer] other than off it is removed
/// from both phones once the timer has run out since the receiver read it.
class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.coupleId,
    required this.senderId,
    required this.kind,
    required this.createdAt,
    this.expiresAt,
    this.text,
    this.durationMs,
    this.mediaPath,
    this.seenAt,
    this.deliveredAt,
    this.pending = false,
    this.locked = false,
    this.ttlSeconds = 0,
    this.reply,
  });

  final String    id;
  final String    coupleId;
  final String?   senderId;
  final ChatKind  kind;
  final DateTime  createdAt;
  /// When it is removed (read time + timer); null while it has no timer running.
  final DateTime? expiresAt;
  final String?   text;
  /// Length of a voice note.
  final int?      durationMs;
  /// Where the sealed photo or voice note is in Storage.
  final String?   mediaPath;
  /// When the receiver read it (your own messages: when their read receipt arrived).
  final DateTime? seenAt;
  /// When it reached the partner's phone (your own messages only).
  final DateTime? deliveredAt;
  /// Your own message that has not reached the server yet (waiting for a connection).
  final bool      pending;
  /// This phone could not open the message (the couple key has not arrived yet).
  final bool      locked;
  /// The sender's timer: how long the message lives once it has been seen.
  final int       ttlSeconds;
  /// The message this one answers, if it is a reply.
  final ChatReply? reply;

  bool get isSeen => seenAt != null;
  bool get isDelivered => deliveredAt != null;
  bool isMine(String userId) => senderId == userId;
  bool isExpired(DateTime now) => expiresAt != null && !now.isBefore(expiresAt!);

  @override
  List<Object?> get props => [id, kind, text, durationMs, mediaPath, seenAt, deliveredAt, pending, expiresAt, locked, ttlSeconds, reply];
}

/// A line in the chat that says the timer was changed ("You set messages to vanish 1 minute after seen").
/// It is shown where the change happened, after the latest message at that moment, and only on the
/// phones that had the chat open then: it is not stored on the server.
class ChatTimerNotice extends Equatable {
  const ChatTimerNotice({required this.at, required this.timer, required this.byMe});

  final DateTime  at;
  final ChatTimer timer;
  final bool      byMe;

  @override
  List<Object?> get props => [at, timer, byMe];
}
