# Security and encryption

Goal: nobody but the two partners can read their content, **including the developer and anyone with database or Storage access**. This is delivered in phases (E0 to E5, see the plan in the repo history). This page records the threat model, the design and what is built so far.

## Status

| Phase | What | State |
|---|---|---|
| E0 | Crypto foundation: `CryptoService`, `KeyService`, key storage, recovery phrase, security code | **Built, not used by any feature yet** |
| E1 | Identity keys published, pairing handshake, security-code verification, recovery and partner approval | **Built** (database migration `e2ee_keys.sql` must be applied) |
| E2 | Text content encrypted (moods, bucket list, timeline, answers, memory titles, next meet, notification details) | Planned |
| E3 | Memory images, strokes (stored and live), locations | Planned |
| E4 | Local caches encrypted at rest, local date reminders | Planned |
| E5 | Re-encrypt existing data, then require encryption on new rows | Planned |

Until E2 ships, **content is still stored readable on the server.** E1 only sets up the keys.

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
7. **Recovery:** a 12-word phrase is shown once and confirmed with a three-word quiz; only the sealed backup goes to the server, bound to the account. A new phone restores with the phrase: the backup is opened and its public key compared **before anything is written**, so a wrong phrase, or an old backup the server kept after a reset, can never replace or wipe the keys on the phone. A restored phone confirms the code again before it takes the couple key. Or the person resets keys and waits for the partner's approval.
8. **Every operation runs one at a time**, so a sync cannot publish an old key over a reset.
9. **Leaving a couple** forgets that couple's key. Keys are stored per account on the phone, so signing out and in keeps them; deleting the account wipes them. The Android keystore is configured so a storage error is reported as an error and never silently wipes the keys.

Screens: Profile -> **Security** (`SecurityScreen`): status, security code (verify / approve), recovery phrase, restore, reset. The pairing success screen shows "Securing your connection" while the keys are set up. `EncryptionSyncGate` (in the app shell) runs `sync()` when the main screens open and when the app returns to the foreground.

Not stored: the recovery phrase is never saved on the phone, so it cannot be shown again; a **new** phrase can be made at any time (it replaces the backup).

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

- **Key rotation:** there is one couple key per couple (version 1) and it is not rotated when the partner's keys change (the partner approves the new keys and keeps reading the same history). A lost or stolen old phone could still hold the key. Rotation (key version 2, re-encrypting content) should be added with the content phases.
- **Nonce budget:** values are encrypted with random 96-bit nonces under one key. That is safe up to roughly 2^32 messages per key; before live drawing chunks are encrypted (E3), add rotation or a counter so the budget cannot be exhausted.
- **Screenshots and the clipboard:** the recovery phrase screen does not block screenshots or screen recording, and Dart cannot erase secrets from memory.
- **A trusted partner can still deny access** by overwriting your sealed copy; you then see "waiting for approval", never a wrong key. The server can do the same. Neither learns anything.
- **Metadata** (who, when, how often) is not hidden.
