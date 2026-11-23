import 'dart:typed_data';

import '../entities/chat_message.dart';

abstract interface class IChatRepository {
  /// How long messages live after they are seen: ONE setting for the couple, so a change by either partner
  /// applies to both, to the messages sent from then on (the server stamps each message with it). This is
  /// the last value this phone knew; [watchTimer] keeps it up to date.
  ChatTimer get timer;

  /// Sets the couple's timer. Throws when the server cannot be reached.
  Future<void> setTimer({required String coupleId, required ChatTimer timer});

  /// The couple's timer: its current value, then every change (by either partner).
  Stream<ChatTimer> watchTimer(String coupleId);

  /// The couple's messages that still exist, oldest first; updates live. A message that expired is
  /// removed by the server, but this stream does not report deletions: callers also drop messages
  /// whose [ChatMessage.expiresAt] has passed.
  Stream<List<ChatMessage>> watchMessages(String coupleId);

  /// Each send returns true when it reached the server and false when it waits for a connection.
  /// Everything is sealed on this phone first; without the couple key it throws `EncryptionNotReady`.
  Future<bool> sendText({required String coupleId, required String userId, required String text});
  Future<bool> sendImage({required String coupleId, required String userId, required Uint8List bytes});
  Future<bool> sendVoice({required String coupleId, required String userId, required Uint8List bytes, required int durationMs});

  /// The receiver has seen these messages: the timer its sender chose starts.
  Future<void> markSeen(List<String> ids);

  /// The decrypted photo or voice note, or null if it cannot be loaded. Kept in memory only.
  Future<Uint8List?> loadMedia(ChatMessage message);

  /// Tells the partner this user is looking at the chat (so a message needs no push), and takes it back.
  Future<void> enterChat({required String coupleId, required String userId});
  Future<void> leaveChat({required String coupleId, required String userId});

  /// Deletes [id] for both partners (the sealed photo or voice file goes too). Either partner may delete
  /// any message. Needs a connection: throws when it cannot reach the server, so the caller can say so.
  Future<void> deleteMessage({required String coupleId, required String userId, required String id});

  /// The ids of messages the PARTNER deleted, as it happens (the table stream does not report deletions).
  Stream<String> watchDeleted(String coupleId);

  /// Deletes the whole chat for both partners (all photos and voice notes too). Throws when the server
  /// cannot be reached.
  Future<void> clearChat({required String coupleId, required String userId});

  /// Fires when the PARTNER clears the chat.
  Stream<void> watchCleared(String coupleId);

  /// How many of the PARTNER's messages this user has not seen yet (and that still exist), live: the
  /// current number first, then each change. Used for the badge on Home.
  Stream<int> watchUnreadCount({required String coupleId, required String userId});
}
