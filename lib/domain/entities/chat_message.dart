import 'package:equatable/equatable.dart';

enum ChatKind {
  text,
  image,
  voice;

  static ChatKind fromKey(String key) => values.firstWhere((k) => k.name == key, orElse: () => ChatKind.text);
}

/// How long a message lives once the receiver has seen it. Chosen by the sender for the messages they send
/// and stored with each message (the server accepts only these values).
enum ChatTimer {
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

  /// What a new chat starts with, and what an unknown stored value falls back to.
  static const defaultTimer = ChatTimer.oneDay;

  static ChatTimer fromSeconds(int? seconds) =>
      values.firstWhere((t) => t.seconds == seconds, orElse: () => defaultTimer);
}

/// One message of the private chat. It disappears for both partners after the sender's [ChatTimer]
/// has run out since the receiver saw it, and after [unseenLife] if it never is (the server enforces both).
class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.coupleId,
    required this.senderId,
    required this.kind,
    required this.createdAt,
    required this.expiresAt,
    this.text,
    this.durationMs,
    this.mediaPath,
    this.seenAt,
    this.locked = false,
  });

  /// How long a message nobody has seen stays.
  static const unseenLife = Duration(days: 1);

  final String    id;
  final String    coupleId;
  final String?   senderId;
  final ChatKind  kind;
  final DateTime  createdAt;
  final DateTime  expiresAt;
  final String?   text;
  /// Length of a voice note.
  final int?      durationMs;
  /// Where the sealed photo or voice note is in Storage.
  final String?   mediaPath;
  final DateTime? seenAt;
  /// This phone could not open the message (the couple key has not arrived yet).
  final bool      locked;

  bool get isSeen => seenAt != null;
  bool isMine(String userId) => senderId == userId;
  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  @override
  List<Object?> get props => [id, kind, text, durationMs, mediaPath, seenAt, expiresAt, locked];
}
