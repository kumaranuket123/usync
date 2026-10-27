# Contributing

## Workflow
1. Branch from `main`; open a PR. CI must pass (`flutter analyze`, `flutter test`).
2. Follow the layering in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Domain imports nothing from data/presentation.
3. New feature: use the `add-feature` skill (or the checklist in CLAUDE.md), and add `docs/features/<feature>.md`.
4. Schema change: add `supabase/migrations/<name>.sql` with RLS, apply it, run Supabase advisors.
5. Prefer theme tokens (`app_colors`, `app_text_styles`) over hard-coded styles.

## Testing
`flutter test` (also run by CI). Layout:

| Path | What it covers |
|---|---|
| `test/core/` | Services and utilities: outbox queue, session/TTL/signed-URL caches, network error mapping, auth messages |
| `test/presentation/` | BLoCs (`PairingBloc`, `MoodBloc`, `SettingsBloc`) against hand-written fakes of the `I*Repository` interfaces |
| `test/data/` | Repositories (`CoupleRepository`, `MoodRepository`), models, and the Realtime channel source |

Repository tests use a real `SupabaseClient` with a stubbed HTTP layer (`test/data/repository_harness.dart`), so query building, RPC calls and row parsing run for real without a network. Outbox-backed repositories run against a temp Hive directory. No mocking packages are needed.

For new code: fake the `I*Repository` interface when testing a BLoC; use `FakeBackend` when testing a repository; add a test with every new service or repository change.

## Commits
Imperative, one logical change each (e.g. "Add custom moods feature").
