import 'dart:typed_data';

import '../entities/chat_message.dart';

/// The private chat, WhatsApp / Signal style: the history lives on this phone; the server only carries a
/// message until the partner's phone has collected it (the phone saves it, then tells the server to delete it).
abstract interface class IChatRepository {
  /// Starts collecting the partner's messages (and receipts) for this couple, once; calling it again for
  /// the same user and couple does nothing. Home and the chat both call it, so messages are saved as soon
  /// as the app is open.
  Future<void> startInbox({required String coupleId, required String userId});

  /// Sign-out, or the couple ended: stops collecting and wipes the history kept on this phone.
  Future<void> reset();

  /// How long messages live on the phones after being read: ONE setting for the couple (see [ChatTimer.off]).
  /// This is the last value this phone knew; [watchTimer] keeps it up to date.
  ChatTimer get timer;

  /// Sets the couple's timer. Throws when the server cannot be reached.
  Future<void> setTimer({required String coupleId, required ChatTimer timer});

  /// The couple's timer: its current value, then every change (by either partner).
  Stream<ChatTimer> watchTimer(String coupleId);

  /// The newest messages on this phone, oldest first, updated live. It starts with one page; [loadOlder]
  /// adds more. Messages whose timer has run out may still be listed until [purgeExpired] runs, so callers
  /// also drop those whose [ChatMessage.expiresAt] has passed.
  Stream<List<ChatMessage>> watchMessages(String coupleId);

  /// Adds one more page of older messages to what [watchMessages] reports. Returns whether even older ones remain.
  Future<bool> loadOlder();

  /// Whether messages older than those reported by [watchMessages] exist.
  bool get hasOlder;

  /// Removes the messages whose timer has run out, from this phone.
  Future<void> purgeExpired();

  /// [replyTo] makes the message a reply to another; it travels inside the sealed content.
  /// The message is on this phone's screen at once. Each send returns true when it reached the server and
  /// false when it waits for a connection. Everything is sealed on this phone first; without the couple key
  /// it throws `EncryptionNotReady`.
  Future<bool> sendText({required String coupleId, required String userId, required String text, ChatReply? replyTo});
  Future<bool> sendImage({required String coupleId, required String userId, required Uint8List bytes, ChatReply? replyTo});
  Future<bool> sendVoice({required String coupleId, required String userId, required Uint8List bytes, required int durationMs, ChatReply? replyTo});

  /// The user has read these partner messages: the timer starts on this phone, and a read receipt goes to
  /// the partner so their phone starts it too and shows the blue ticks.
  Future<void> markSeen(List<String> ids);

  /// The photo or voice note of [message] (already on this phone), or null.
  Future<Uint8List?> loadMedia(ChatMessage message);

  /// Tells the partner this user is looking at the chat (so a message needs no push), and takes it back.
  Future<void> enterChat({required String coupleId, required String userId});
  Future<void> leaveChat({required String coupleId, required String userId});

  /// Deletes [id] from this phone only.
  Future<void> deleteForMe(String id);

  /// Deletes one of the user's OWN messages from both phones (the partner's phone removes it when it hears,
  /// also later if it is offline). Needs no connection: the request is queued.
  Future<void> deleteForEveryone({required String coupleId, required String userId, required String id});

  /// Clears the chat on this phone; with [forEveryone] the partner's phone is cleared too.
  Future<void> clearChat({required String coupleId, required String userId, required bool forEveryone});

  /// How many of the PARTNER's messages this user has not read yet, live: the current number first, then each
  /// change. Used for the badge on Home.
  Stream<int> watchUnreadCount({required String coupleId, required String userId});
}
