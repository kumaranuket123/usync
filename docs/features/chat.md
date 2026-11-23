# Feature: Private chat

A WhatsApp-style chat between the two partners: text, photos and voice notes. Everything is end-to-end encrypted on the phone, and a message disappears for both partners a while after the receiver has seen it: the sender chooses 10 seconds, 1 minute, 5 minutes, 1 hour or 1 day (the default). A message nobody opens is deleted after 1 day.

## Screen: Private chat (`/chat`)
Opened from the Home "Chat" pill, the Activity tab card, and a chat notification in the notification list.
- Header: back button, title, "Encrypted · vanishes <timer> after seen" and a **timer button** (⏱ with the current choice) that opens a sheet with 10 seconds / 1 minute / 5 minutes / 1 hour / 1 day. The choice is per person: it sets how long the messages *you* send live once your partner has seen them, applies to new messages only, and is kept on the phone (`PrefsSource.chatTimerSeconds`, default 1 day). The list shows the newest message at the bottom (`ListView(reverse: true)`).
- **Bubbles**: yours on the right (pink), your partner's on the left (cyan). There is no countdown on messages; your own bubbles show a quiet tick, one when sent and two (in colour) once your partner has seen it. A message this phone cannot open (no couple key yet) shows "Locked until your key arrives".
- **Text**: multi-line field (max 2000 characters); the send button replaces the microphone once there is text.
- **Photo**: the add-photo button offers camera or gallery. The picture is shrunk to at most 1600 px at quality 80 before sending. Tap a photo to view it full screen (pinch to zoom).
- **Voice note**: hold the microphone to record (AAC, mono), release to send, slide left to cancel. Under 0.8 s is discarded, 2 minutes is the limit. Played from memory with a play/pause button and progress bar.
- On Android the screen is protected while the chat is open: screenshots, screen recording and the app-switcher preview are blocked (`SecureScreen`, `FLAG_SECURE` in `MainActivity`). iOS cannot block them.

## State
`ChatBloc` (`ChatOpened`, `ChatVisibilityChanged`, `ChatTimerChanged`, `ChatTextSent`, `ChatImageSent`, `ChatVoiceSent`; private `_MessagesChanged`, `_Tick`). `ChatState`: `loading`, `messages` (oldest first, expired ones already left out), `now`, `userId`, `timer`, `notice` (a one-off message: no key, offline, failed).
- A 1-second ticker drops the messages that have expired (it only redraws when one did); the server deletes rows, but Realtime does not report deletes, so the phone drops expired messages itself.
- A partner's message is reported as seen (`mark_chat_seen`) only while the chat is in front and the app is resumed, once per message; a failure is retried on the next change.
- While the chat is in front the phone announces `screen: chat` on Presence (and takes it back when it leaves, goes to the background or is closed).

## Data
- Migrations `supabase/migrations/couple_chat.sql` (apply after `couple_games_slap.sql`), then `couple_chat_timer.sql` (a `ttl_seconds` per message, allowed values 10/60/300/3600/86400, and a 1-day life for unseen messages), then `couple_chat_hardening.sql` (expired rows are no longer readable; clients can read, add and replace chat files but not delete them). Edge Function `supabase/functions/purge-chat/`.
- `chat_messages`: `id` (chosen by the sender), `couple_id`, `sender_id`, `kind` (`text` | `image` | `voice`), `enc`, `media_path`, `ttl_seconds`, `created_at`, `seen_at`, `expires_at`. Clients can only select (RLS `is_active_couple_member`); writes go through the RPCs `send_chat_message` (checks the member, the sender and that the media path is exactly `<couple>/<id>.enc`; a retry of the same id changes nothing) and `mark_chat_seen` (only the partner of the sender: sets `seen_at = now()` and `expires_at = now() + ttl_seconds`). `send_chat_message` takes the sender's `p_ttl` (default 1 day) and refuses any other value than the five choices.
- Sealing: `enc` is `ContentCipher.sealJson` of `{t: text, d: durationMs}` bound to couple, table `chat_messages` and the message id; the photo or voice bytes are `sealBytes` (field `media`) in the private `chat` bucket at `<couple_id>/<message id>.enc`. The server sees only ciphertext, sender, kind, sizes and timestamps (including when it was seen).
- Expiry: the cron job `purge-chat` runs `purge_chat()` every minute: it deletes expired rows (an `AFTER DELETE` trigger queues each `media_path` in `chat_media_trash`), then calls the `purge-chat` Edge Function (same Vault secret as `send-push`) which removes the queued files from Storage. Disconnecting the couple (`couples.disconnected_at` set, which account deletion also does) clears the couple's chat through a trigger.
- Decrypted photos and voice notes are kept in memory only (12 most recent), never written to the phone. The recorder's temporary file is deleted as soon as it has been read.
- Realtime: `chat_messages` is in the `supabase_realtime` publication with full replica identity, so a seen/expiry change reaches the sender's phone.
- Push: `NotifType.chat`, own "Chat" alert-sound group. The text is fixed ("New message 💬": no name, no content). Sent only when the partner is not on the chat screen (Presence) and at most once a minute.
- Sending a message counts toward the day streak (`record_activity`).

## Edge cases
- **No couple key yet**: sending is refused with "Finish securing your connection first: Profile → Security", nothing is queued or sent; received messages show as locked.
- **Offline**: sends go through the `OutboxService` (`chat_message`, with the message id and the media bytes, encrypted at rest on the phone); they are sent in order when the connection is back. The message appears in the chat once it reaches the server.
- **Microphone / camera / photos denied**: the person is told to allow the microphone, or the photo cannot be opened.
- **Partner absent**: the message waits (1 day); its timer starts when they open it.
- **Short timers**: with 10 seconds the phones hide the message at once, but the server deletes it and its file with the next cron run (within a minute); the partner can no longer read the row after it has expired.
- **Not a screenshot-proof chat**: the partner can still photograph the screen or save a photo, and iOS screenshots are not blocked.

## Code
- `lib/domain/entities/chat_message.dart`, `lib/domain/repositories/i_chat_repository.dart`
- `lib/data/repositories/chat_repository.dart`, `lib/data/datasources/remote/chat_media_source.dart`
- `lib/presentation/features/chat/` (`ChatBloc`, `ChatScreen`), `lib/core/services/voice_recorder.dart`, `lib/core/services/secure_screen.dart`
- Tests: `test/domain/chat_message_test.dart`, `test/data/chat_repository_test.dart`, `test/presentation/chat_bloc_test.dart`
