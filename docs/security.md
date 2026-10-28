# Security and encryption

Goal: nobody but the two partners can read their content, **including the developer and anyone with database or Storage access**. This is delivered in phases (E0 to E5, see the plan in the repo history). This page records the threat model, the design and what is built so far.

## Status

| Phase | What | State |
|---|---|---|
| E0 | Crypto foundation: `CryptoService`, `KeyService`, key storage, recovery phrase, security code | **Built, not used by any feature yet** |
| E1 | Identity keys published, pairing handshake, security-code verification, recovery and partner approval | **Built** (database migration `e2ee_keys.sql` must be applied) |
| E2 | Text content encrypted: moods, bucket list, answers, next meet, notification details (memories wait for E3 with their pictures, timeline dates for E4 with local reminders) | **Built** (migration `e2ee_content_text.sql` must be applied, then `min_supported_build` raised) |
| E3 | Binary and live data: memories and pictures (`e2ee_memories.sql`), the shared drawing, saved and live, and the widget (`e2ee_strokes.sql`), locations and the background locate (`e2ee_locations.sql`) | **Built** (E3c migration must be applied) |
| E4 | **E4a** timeline dates sealed + reminders scheduled on the phone (migration `e2ee_timeline.sql`, applied; `remove_milestone_reminders.sql` only at release). **E4b** local storage encrypted at rest: the cached answers, the offline queue and pictures kept on the phone | **Built** |
| E5 | **E5a** each phone seals the older readable content it wrote (`seal_row`, `seal_answer`; migration `e2ee_seal_rows.sql`). **E5b** lock-down: the server refuses unsealed new content (`e2ee_lockdown.sql`, **applied only at release**, with the minimum build raised) | **Built** (nothing in E5 applied yet) |

Until E2 is released, **content is still stored readable on the server.** From E2, new moods, bucket items, answers, next-meet dates and notification details are stored only as ciphertext; memories, timeline, drawings and locations stay readable until E3/E4, and older rows are re-encrypted in E5.

## E1: how the keys are shared (`EncryptionRepository`, `EncryptionBackend`)

What the server stores (migration `e2ee_keys.sql`), none of it readable as a key:
- `user_public_keys`: each person's X25519 **public** key. A person and their active partner can read it; nobody can write it directly (RPC `publish_public_key`).
- `user_key_backups`: the identity key sealed with the recovery phrase; only its owner can read it.
- `couple_keys`: the couple's key sealed separately to each partner's public key; each person can read only their own row. Written only by the RPC `put_couple_keys`: the first writer wins when creating, and you can only replace the **other** partner's copy (approving their new key).
- `disconnect_couple` and `delete_my_account` delete the couple's keys; the public key and backup go with the account.

The protocol, run on every phone by `EncryptionRepository.sync()` (idempotent, never throws):
1. **First time:** make the identity key, publish its public half. A phone that has no key but whose account already has a published one **never makes a new key by itself**: it asks to **restore** (a silent replacement would lock the partner out). Making a key is an explicit step (`KeyService.createIdentity`); everything else only reads the existing one, so no background task or race can mint a second identity. A phone only (re)publishes a key it made itself.
2. **Nothing is shared before the security code is compared.** With both public keys known, the phase is **needsVerification**: the 60-digit code (from both public keys) is shown and both partners compare it out loud. Only after a person confirms it does a phone create the couple key (or adopt the one the partner made). So a partner key swapped by the server cannot be handed the couple's key.
3. **Wrapped keys are authenticated.** A couple key is sealed to the recipient with an ephemeral exchange **and** a static exchange between the two identities (`w2:`). A phone accepts a key only if it was made by itself or by the partner whose key it confirmed. The server can write rows and knows both public keys, but without a private key it cannot produce a key a phone will accept, so it cannot choose the couple's key. Forging or overwriting a row only causes "waiting for approval", never a silent adoption.
4. **A confirmation applies to the exact code the person saw.** "They match" and "Approve" carry that code; if the server serves a different key by the time they are processed, the operation is refused and the page refreshes.
5. **Partner's key changes** (new phone, reset): this phone shows "security code changed" and does **not** trust it. After the person compares the new code, **Approve** re-seals the existing couple key for the new key. Confirming the code alone does not approve it.
6. **"Verified" is the confirmed code**, so it covers both keys: if either of us makes new keys, the old confirmation stops counting.
7. **Recovery:** a 12-word phrase is shown once and confirmed by tapping the right word at three positions (four choices each, no typing; a wrong pick clears and retries); besides paper, the person can **Copy** the phrase (removed from the clipboard after a minute if it is still there, while the app is running) or **Save to…** another app through the share sheet (a password manager, a private note), with a warning not to keep it where others can read it; only the sealed backup goes to the server, bound to the account. A new phone restores with the phrase: the backup is opened and its public key compared **before anything is written**, so a wrong phrase, or an old backup the server kept after a reset, can never replace or wipe the keys on the phone. A restored phone confirms the code again before it takes the couple key. Or the person resets keys and waits for the partner's approval.
8. **Every operation runs one at a time**, so a sync cannot publish an old key over a reset.
9. **Leaving a couple** forgets that couple's key. Keys are stored per account on the phone, so signing out and in keeps them; deleting the account wipes them. The Android keystore is configured so a storage error is reported as an error and never silently wipes the keys.

Screens: Profile -> **Security** (`SecurityScreen`): status, security code (verify / approve), recovery phrase, restore, reset. The pairing success screen shows "Securing your connection" while the keys are set up. `EncryptionSyncGate` (in the app shell) runs `sync()` when the main screens open and when the app returns to the foreground.

Not stored: the recovery phrase is never saved on the phone, so it cannot be shown again; a **new** phrase can be made at any time (it replaces the backup).

## E2: text content (`ContentCipher`)

- Every sealed value is `u1:` AES-GCM bound to couple, table, row and field, so the server cannot move it elsewhere. Nothing is ever written readable: without the couple key a write throws `EncryptionNotReady` ("Finish securing your connection first: Profile → Security") and the outbox keeps queued changes until the key arrives.
- Readers accept both sealed and older readable rows. A sealed row this phone cannot open shows as locked, never disappears.
- Moods, bucket items: readable columns hold a `🔒`/`custom` placeholder, content is in `enc`. Answers: `answer` is the ciphertext (reveal gate in `get_question_state` unchanged). Next meet: `set_next_meet_enc` RPC, `next_meet_enc`.
- Notifications: `body_text` is a fixed sentence (the push shows only that); the typed words go in `detail_enc` and are shown in the app after decrypting.
- Older builds show placeholders and cannot decrypt, so release E2 together with raising `app_config.min_supported_build`. The old `set_next_meet` RPC clears the sealed date so the two never disagree.
- Not yet: direct writes of readable text by a modified client are not blocked by the server (enforced in E5).

### Notifications carry no names

`notifications.body_text` (what the server stores and the lock-screen push shows) says "Your partner …" and never the sender's name or typed words. The full sentence, with the name, is sealed into `detail_enc` for every notification and shown inside the app after it is opened. The in-app list falls back to the nameless sentence when the detail cannot be opened. Old rows with names are rewritten by `e2ee_lockdown.sql`. This only keeps the name out of notifications: the person's display name still exists in `profiles.username` (it comes from Google sign-in and the partner screen needs it), so it is account metadata, not secret from the database.

## E3b: the shared drawing (`CanvasStrokeCodec`)

- A finished stroke is one sealed value, `canvas_strokes.enc` (colour, width, eraser flag, points), bound to couple, table and stroke id. Who drew it, the stroke id and when stay readable (streaks count on them). Older readable strokes are still read.
- Live strokes over Realtime: `stroke_start` and each `stroke_chunk` carry an `enc` value bound to the stroke id and its part (`start`, `chunk:<seq>`), so a message cannot be moved to another stroke or part. `stroke_end` (stroke id and chunk count) and `canvas_clear` stay readable.
- Receivers open live events one after another, so an end is never handled before its start; a message that does not open is ignored.
- Strokes are sealed when a stroke finishes, so only ciphertext waits in memory and in the outbox. A change queued by an older version of the app is sealed before it is sent. Without the couple key the canvas shows "Finish securing your connection first" and nothing is drawn or sent.
- The home-screen widget (also in the background push isolate) builds its own cipher from secure storage and opens the strokes itself; if it cannot read them yet it keeps the last picture. The rendered widget PNG stays readable in the app-private folder, because the launcher has to draw it.
- **Nonce budget:** every message uses a fresh random 96-bit nonce under the one couple key. That stays safe far beyond any realistic use (the risk only becomes meaningful after billions of messages under the same key); the practical limit for a couple is far below it. Key rotation (see below) would reset it.

## E3c: locations (`LocationRepository`)

- A person's one `locations` row keeps latitude, longitude, accuracy and the time of the fix in `enc` (bound to couple, table and that person's user id). The readable columns are written as null on every save, which also clears an older readable position. `allow_background` and `updated_at` stay readable (the push function needs the first).
- The time shown comes from inside the sealed value, so a stale value replayed by the server shows its real age. A row this phone cannot open shows as no location.
- Without the couple key `syncOwnLocation` returns `LocationAccess.notSecured` before touching the GPS, and the screen says to finish securing the connection. The background locate answer builds its own cipher from secure storage and simply does not answer without a key.
- The server still sees that a location was updated and when, and the person's opt-in to background requests.

## E4a: timeline dates and local reminders

- A custom date's title, note, emoji, day and "every year" flag are sealed into `milestones.enc` (bound to the row); the readable columns hold a placeholder (`🔒`, and a fixed 1970 day so the server cannot see when it is). Milestones the server writes itself (streaks, first connect) and older readable dates stay readable and are still shown.
- The server-side reminder job (`send_milestone_reminders`) needs readable dates, so it now skips sealed ones, and `remove_milestone_reminders.sql` removes the job and the function. **Apply that second migration only when the build with local reminders is the minimum supported build**, otherwise existing users lose their reminders.
- Reminders are local notifications scheduled by each phone (`ReminderService`, `flutter_local_notifications`): 9:00 local time, one-off dates on their day, yearly dates for the next three anniversaries (each with its own count; 29 February falls on the 28th in other years). Everything is rescheduled when the timeline loads or changes, when the app starts or returns to the foreground (`ReminderSync`, so a partner who never opens the timeline still gets them), and cleared on sign-out, disconnect and account deletion. The reminder text is built on the phone and never leaves it.
- Android: inexact alarms (no exact-alarm permission), re-created after a restart by the plugin's boot receiver. iOS: permission is the one asked for push; the iOS side is not verified in this environment.
- Without the couple key adding a date is refused with the usual "finish securing your connection" message.

## E4b: local storage at rest (`DeviceKey`)

- One random 256-bit **device key** per phone, created on first use and kept only in the Android Keystore / iOS Keychain (`usync.local.v1`, outside the account's `e2ee.` namespace so signing out or deleting an account never touches it). It is not the couple key and is never sent anywhere. A restore of the app's folder onto another phone cannot be read, because the key does not move.
- The Hive boxes `session_cache` (cached server answers, which are themselves still sealed content) and `outbox` (queued changes, including drawings waiting to be sent) are now `session_cache_enc` and `outbox_enc`, encrypted with Hive's AES cipher under the device key. The first start copies the old unencrypted boxes over (only into an empty box, so an interrupted copy never repeats a queued change) and deletes them. Hive encrypts values, not key names: the names are ids like `moods:<couple id>`, which is metadata, not content.
- Pictures kept on the phone (`usync/memories/<user>/<id>.png`) are sealed files (AES-GCM, bound to the memory id). Nothing opens a path directly: `LocalMemoryImages.read` returns bytes, and the share sheet and gallery get a short-lived readable copy that is deleted afterwards (shares are removed after two minutes and swept on the next share). Pictures from earlier versions are sealed on first use and by a sweep at start-up. Earlier versions also cached readable copies in the image cache: that is emptied once.
- If the Keystore/Keychain cannot be used, the app still starts: for that run the boxes use a key that exists only in memory, so offline caching and queued changes do not survive a restart, and no picture is saved. Nothing readable is ever kept instead.
- A box that the key cannot open (key lost) holds only cache and queued changes; it is discarded and started empty.
- Still readable on the phone, by necessity or choice: the home-screen widget picture (the launcher draws it), copies the person chooses to save to the gallery, and settings (theme, switches). Deleting a file is not a secure erase on flash storage.

## E5: sealing older content and locking down

- **E5a, sealing (`LegacyContentSealer`, `seal_row`, `seal_answer`).** Content written before encryption is still readable on the server. Once a phone has the couple key (checked after each key sync, at most every 15 minutes), it seals the rows **it wrote itself** — moods, bucket items, answers, memories (text and picture), custom timeline dates, drawing strokes — and the shared next-meeting date. The functions only accept the caller's own row, only while it is still readable, and replace the readable content with the same placeholders new rows use. A row is sealed whole or not at all, so it is safe to stop at any point; the content shapes match what each repository reads (tested for every kind). A memory's readable picture is downloaded, sealed, uploaded as `<couple>/<id>.enc`, and the old object removed only after the row points at the new one. An older readable location is replaced by the next refresh, or removed if sharing is off. Rows written by someone who never opens the updated app stay readable until they do.
- **E5b, lock-down (`e2ee_lockdown.sql`).** **Apply only at release**, when `app_config.min_supported_build` is the build that seals everything: older builds write readable content and would be refused. It adds triggers that refuse any new row that is not sealed (with the exact placeholders the app writes), removes the clients' right to rewrite the readable columns of existing rows, drops the old `set_next_meet` function (which wrote the date readably), and replaces the text of old notifications that quoted typed words. It does not touch existing readable rows; those only go through `seal_row`.
- After the lock-down the server can no longer be sent readable content by a modified client either (before it, that was the known gap). What remains readable is the metadata listed above.
- To finish for good: once every person has opened the updated app, the readable leftovers can be counted (`count(*) where enc is null`) and, if some author never returns, deleted or left as they are.

## What it protects, and what it cannot

**Protected (once E2 to E5 ship):** content in the database and Storage, backups, a database leak, Supabase staff, and the developer reading rows. The server will hold only ciphertext.

**Still visible to the server / Google (metadata):** who is paired with whom; when and how often things are created; counts and streaks; the kind of activity in a notification; device push tokens; the account email and name (from Google sign-in); avatar; relationship type.

**Notifications:** the push and the `notifications` table will carry only a fixed sentence and the kind of activity (for example "Alex shared a mood 💭"), never words you typed. The details are stored encrypted and shown inside the app.

**Not defended by encryption alone:**
- A malicious app update by the developer could steal keys (mitigated by Play signing and by partners comparing security codes).
- A server that swaps public keys at pairing is caught only if the partners really compare the **security code** out loud. The app refuses to share any key until they have confirmed it, but a person who confirms without comparing defeats this.
- A partner's screenshot, a compromised phone, map tiles (OpenStreetMap sees the viewed area), and the Google Maps hand-off.

## Design (E0, in `lib/core/crypto/`)

- **Envelope** (`CryptoService.seal/open`): AES-256-GCM. Bytes are `[version 1][nonce 12][ciphertext][tag 16]`; as text, `u1:` + base64url. A fresh random nonce every time. The associated data (`fieldAad`) binds a value to its couple, table, row and field, so ciphertext cannot be moved to another row, field or couple.
- **Key wrapping** (`wrapKey/unwrapKey`): a key is sealed to the recipient's X25519 public key with a fresh ephemeral key and HKDF-SHA256 (`w1:` + base64url). The associated data names what the key is for. An all-zero shared secret (a low-order public key) is refused.
- **Identity key** (`KeyService`): an X25519 key from a random 32-byte seed. Only the seed is stored, in the Android Keystore / iOS Keychain (`flutter_secure_storage`, items stay on the device; Android backup is off). The public half is what gets shared.
- **Couple key**: random 256 bits per couple, stored per couple id and version in the same secure store.
- **Recovery phrase**: 12 BIP39 words (128 bits). They derive, through HKDF, a key that seals a backup of the identity seed; the sealed backup is what may be stored on the server. Without the phrase it cannot be opened.
- **Security code** (`securityCode`): 60 digits (12 groups of 5) from SHA-512 over both public keys in sorted order. The same for both partners, and different if either key was swapped.
- `KeyService` depends only on a `SecureKeyStore`, never on the service locator, so it can run in a background isolate. Algorithms are looked up per call, so the native implementation that the `cryptography_flutter` plugin registers is used where available (the pure-Dart one otherwise).

## Rules for anyone changing this code

- Never log or print keys, phrases, plaintext content or seeds.
- Never store a key outside the `SecureKeyStore`.
- A value is bound to its place by its associated data; always pass the real couple, table, row and field.
- A new envelope version must keep reading the old one.
- Tests use published vectors (RFC 7748 X25519, RFC 5869 HKDF, the BIP39 phrase) and tamper/wrong-key/wrong-context cases; keep them passing.

## Dependencies

`cryptography` 2.9.0, `cryptography_flutter` 2.3.4, `flutter_secure_storage` 10.3.4 (11.x conflicts with `package_info_plus` on `win32` for now), `bip39_mnemonic` 4.1.0. Versions are pinned.

## Known limits and later work

- **Older readable content from absent authors** stays readable until they open the updated app (see E5).
- **Key rotation:** there is one couple key per couple (version 1) and it is not rotated when the partner's keys change (the partner approves the new keys and keeps reading the same history). A lost or stolen old phone could still hold the key. Rotation (key version 2, re-encrypting content) should be added with the content phases.
- **Nonce budget:** values are encrypted with random 96-bit nonces under one key. That is safe up to roughly 2^32 messages per key; before live drawing chunks are encrypted (E3), add rotation or a counter so the budget cannot be exhausted.
- **Screenshots and the clipboard:** the recovery phrase screen does not block screenshots or screen recording, and Dart cannot erase secrets from memory.
- **A trusted partner can still deny access** by overwriting your sealed copy; you then see "waiting for approval", never a wrong key. The server can do the same. Neither learns anything.
- **Metadata** (who, when, how often) is not hidden.
