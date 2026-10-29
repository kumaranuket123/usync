# Feature: Trust and privacy message

Couples share very private things, so the app says plainly how it protects them, in the places people look, without a popup on every open. Details of the encryption itself are in [security.md](../security.md).

---

## Wording (`core/constants/trust_copy.dart`)

One source for every message, so claims cannot drift apart: a summary ("encrypted on your phone, only you and your partner can read them"), the promise ("no ads, no analytics, we never sell your data"), and three lists: what is encrypted, what the server can still see, and the services that handle data (Supabase, Google sign-in and push, OpenStreetMap).

It deliberately does **not** say "no data is shared with third parties": those services do process data, and the [privacy policy](../privacy-policy.html) says so. Keep the lists true when the encryption phases or the services change.

## Where it shows

| Place | What |
|---|---|
| Welcome (`OnboardingScreen`) | Fifth slide, "Private by design" (`OnboardingState.lastPage` is 4) |
| Login (`LoginScreen`) | The summary and promise under the Google button, with "How we protect you" and "Privacy Policy" links |
| Home (`EncryptionBadge`) | A pill under the header showing the **live** state (below) |
| Profile → Security | "What is protected" card at the bottom |
| About | "End-to-end encryption" entry |

`showTrustSheet` (`shared/widgets/trust_sheet.dart`) is the "How we protect you" sheet: the three lists, the promise, a Privacy Policy button and, when opened from a signed-in screen, a shortcut to Profile → Security.

## The Home badge

`EncryptionBadge` follows `IEncryptionRepository.changes` (every state `sync()` or an operation produces; `EncryptionSyncGate` syncs on open and on resume). `encryptionBadgeFor(phase)` decides the text, so the app never claims more than is true:

| Phase | Badge | Tap |
|---|---|---|
| `ready` | 🔒 End-to-end encrypted | trust sheet |
| `waitingForPartner`, `noCouple`, `waitingForKey` | ⏳ Securing your connection… | trust sheet |
| `needsVerification` | 🔑 Compare your security code | Profile → Security |
| `needsRestore`, `needsApproval`, `partnerKeyChanged` | ⚠️ Action needed to stay secure | Profile → Security |
| `unknown` | hidden: nothing is claimed until the phone has checked | |

## Release note

The welcome and login wording describes the encryption build, so ship it with that release ([release-encryption.md](../release-encryption.md)). The privacy policy still says timeline entries are not encrypted yet, which is out of date now that custom dates are sealed (E4a): update and re-publish it with the release.
