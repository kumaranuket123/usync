import 'dart:typed_data';

import '../entities/chat_message.dart';

abstract interface class IChatRepository {
  /// How long the messages this user sends live after they are seen. Kept on this phone; each message
  /// carries the value it was sent with.
  ChatTimer get timer;
  Future<void> setTimer(ChatTimer timer);

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
}
