# Feature: Pairing

Links two accounts into one couple. One partner generates a short invite code, the other enters it. Pairing is a precondition for every other feature: all shared data is scoped by `couple_id`.

---

## Screens

| Route | Screen | Purpose |
|---|---|---|
| `/pair-invite` | `PairInviteScreen` | Shows this user's invite code and waits for the partner to use it. Below it, "Use a different account" and an `AccountLinks` row (**About Usync**, **Privacy Policy**, **Delete account**), so someone who is signed in but not paired yet can still read about the app and policy and delete their account |
| `/pair-join` | `PairJoinScreen` | Enter the partner's code |
| `/pair-success` | `PairSuccessScreen` | Confirmation after a successful join |

Pairing routes are outside the `ShellRoute` and always reachable (see `RouteGuards`), so an unpaired signed-in user can get to them.

## State (`PairingBloc`)

| Event | Result state |
|---|---|
| `GenerateCodeRequested(userId)` | `PairingLoading` -> `CodeGenerated(code)` / `PairingError` |
| `JoinWithCodeRequested(code, userId)` | `PairingLoading` -> `PairingSuccess(couple)` / `PairingError` |
| `WatchPartnerJoined(userId)` | `PartnerJoined` when someone uses this user's code |
| `PairingReset` | `PairingInitial` |

`WatchPartnerJoined` uses `emit.forEach` on `ICoupleRepository.watchPartnerJoined`, so listening stops when the screen closes the bloc.

## Data

- `invite_codes` (durable): `code` (primary key), `user_id`, `expires_at`. RLS: you can insert, read and delete only your own.
- Code format: 4 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no look-alike characters), generated with `Random.secure()`, valid 24 hours. A collision is rejected by the primary key and retried up to 5 times.
- **`join_with_code(p_code)` RPC** (`SECURITY DEFINER`) does the pairing atomically: locks the code row, rejects invalid, expired, own-code and already-paired cases, inserts the `couples` row, sets `profiles.couple_id` for both users, and deletes the code. Clients cannot write `couples` directly.
- Ending a couple is `disconnect_couple`, described in [settings](settings.md).

## Edge cases

- Code used twice or after expiry: the RPC raises `Invalid invite code` / `Invite code expired`; the screen shows the message.
- One of the two is already paired: `One of you is already paired`.
- Entering your own code: `Cannot pair with yourself`.
