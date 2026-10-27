# Feature: Offline support

Changes made without a connection are kept on the device and delivered, in order, when the connection returns. Reads use local caches so screens open quickly.

---

## Outbox (`core/services/outbox_service.dart`)

`OutboxService` is the single entry point: `submit(type, payload)`.

1. If online and nothing is waiting, send immediately (20 s timeout; a timeout counts as lost connection).
2. Otherwise, or on a network error, append to a Hive box and return `false`.
3. `flush()` sends oldest first, stops at the first network failure, and runs on reconnect (`connectivity_plus`) and every 30 s while anything is pending.
4. Non-network failures (a rejected row) are retried up to 5 times, then dropped so they cannot block the queue.
5. Entries with an unknown type (written by a newer app version) are kept.
6. `clear()` runs at sign-out so one account's changes are never sent as another's.

Handlers must be idempotent: ids are generated when the change is made, so a send whose reply was lost can safely repeat.

### Registered handlers

| Type | Repository |
|---|---|
| `mood` | `MoodRepository` |
| `milestone` | `MilestoneRepository` |
| doodle memory | `MemoryRepository` |
| strokes, stroke batch, clear | `CanvasRepository` |

## UI

`OfflineBanner` shows "You are offline", "N changes waiting to send" or "Sending N changes..." as a floating pill; no layout shifts.

## Caches

`SessionCache` (Hive), `IdentityCache`, `TtlCache`, `SignedUrlCache` reduce round trips; memory pictures are also saved on-device (see [memories](memories.md)). Network failures are classified by `core/utils/network_errors.dart`.

## Tests

`test/core/outbox_service_test.dart`, `ttl_cache_test.dart`, `signed_url_cache_test.dart`, `session_cache_test.dart`, `network_errors_test.dart`.
