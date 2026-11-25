import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/chat_message.dart';

ChatMessage _msg({DateTime? seenAt, DateTime? expiresAt, String? sender = 'a'}) => ChatMessage(
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

  test('a message with no timer running never expires', () {
    expect(_msg().isExpired(now.add(const Duration(days: 3650))), isFalse);
  });

  test('the timer choices are Off, 10 seconds, 1 minute, 5 minutes, 1 hour and 1 day, Off by default', () {
    expect(ChatTimer.values.map((t) => t.seconds), [0, 10, 60, 300, 3600, 86400]);
    expect(ChatTimer.defaultTimer, ChatTimer.off);
    expect(ChatTimer.off.isOff, isTrue);
    expect(ChatTimer.fromSeconds(300), ChatTimer.fiveMinutes);
    expect(ChatTimer.fromSeconds(null), ChatTimer.off);
    expect(ChatTimer.fromSeconds(7), ChatTimer.off);
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
