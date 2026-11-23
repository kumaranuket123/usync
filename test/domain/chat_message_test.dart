import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/chat_message.dart';

ChatMessage _msg({DateTime? seenAt, required DateTime expiresAt, String? sender = 'a'}) => ChatMessage(
      id: '1', coupleId: 'c', senderId: sender, kind: ChatKind.text,
      createdAt: DateTime(2026, 1, 1), expiresAt: expiresAt, seenAt: seenAt,
    );

void main() {
  final now = DateTime(2026, 1, 1, 12);

  test('a message is expired exactly when its time has come', () {
    expect(_msg(expiresAt: now.add(const Duration(seconds: 1))).isExpired(now), isFalse);
    expect(_msg(expiresAt: now).isExpired(now), isTrue);
    expect(_msg(expiresAt: now.subtract(const Duration(minutes: 1))).isExpired(now), isTrue);
  });

  test('the timer choices are 10 seconds, 1 minute, 5 minutes, 1 hour and 1 day, 1 day by default', () {
    expect(ChatTimer.values.map((t) => t.seconds), [10, 60, 300, 3600, 86400]);
    expect(ChatTimer.defaultTimer, ChatTimer.oneDay);
    expect(ChatTimer.fromSeconds(300), ChatTimer.fiveMinutes);
    expect(ChatTimer.fromSeconds(null), ChatTimer.oneDay);
    expect(ChatTimer.fromSeconds(7), ChatTimer.oneDay);
    expect(ChatMessage.unseenLife, const Duration(days: 1));
  });

  test('knows whose message it is', () {
    expect(_msg(expiresAt: now).isMine('a'), isTrue);
    expect(_msg(expiresAt: now).isMine('b'), isFalse);
  });

  test('the kinds round-trip through their keys, unknown falls back to text', () {
    for (final k in ChatKind.values) {
      expect(ChatKind.fromKey(k.name), k);
    }
    expect(ChatKind.fromKey('hologram'), ChatKind.text);
  });
}
