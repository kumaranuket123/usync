# Usync

Realtime emotional connection for couples. Two partners pair with an invite code, then share a live drawing canvas, synchronised touch, moods, a daily question, memories, a timeline, and (opt-in) location. Android + iOS, portrait only.

[![CI](https://github.com/kumaranuket123/usync/actions/workflows/ci.yml/badge.svg)](https://github.com/kumaranuket123/usync/actions/workflows/ci.yml)

## Features

| Feature | What it does | Spec |
|---|---|---|
| Pairing | Invite code, `join_with_code` RPC, one couple per user | [pairing](docs/features/pairing.md), [authentication](docs/features/authentication.md) |
| Shared canvas | Live stroke sync between partners; finished strokes persisted | [canvas](docs/features/canvas.md) |
| Touch sync | Both partners touching at once, via Presence + Broadcast | [touch_sync](docs/features/touch_sync.md) |
| Mood | Preset and custom moods, partner's latest mood on home | [mood](docs/features/mood.md) |
| Memories | Saved doodles/images in a private bucket, signed URLs | [memories](docs/features/memories.md) |
| Timeline & streaks | Milestones, custom dates, streak tracking | [timeline](docs/features/timeline.md) |
| Question of the day | One shared question a day; answers stay private until both partners reply | [question-of-the-day](docs/features/question-of-the-day.md) |
| Location | Opt-in partner location on a map | [location](docs/features/location.md) |
| Home-screen widget | Android widget for Live Doodle | [home-widget](docs/features/home-widget.md) |
| App lock | Biometric lock | [app-lock](docs/features/app-lock.md) |
| Push | DB trigger -> Edge Function -> FCM | [push-notifications](docs/features/push-notifications.md) |
| Offline | Local cache + outbox queue that replays in order | [offline](docs/features/offline.md) |

## Tech stack

Flutter 3.41.9 (pinned with FVM) · BLoC · GetIt · go_router · Supabase (Postgres + RLS, Auth, Realtime, Storage, Edge Functions) · Firebase (FCM delivery only) · Hive / SharedPreferences · GitHub Actions.

## Architecture at a glance

```
presentation (screens + BLoCs)  ->  domain (entities + I*Repository)  <-  data (repositories, datasources, models)
                    \_________________ core: DI, router, theme _________________/
```

Dependencies point inward: `presentation` and `data` depend on `domain`; `domain` depends on nothing. Full detail, data-flow diagrams and design decisions: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/adr/](docs/adr/).

## Getting started

```bash
fvm use            # or install Flutter 3.41.9
flutter pub get
flutter analyze
flutter test
flutter run
```

Backend: Supabase project `usync`. Schema in [`supabase/schema.sql`](supabase/schema.sql), incremental changes in [`supabase/migrations/`](supabase/migrations/), push function in [`supabase/functions/send-push/`](supabase/functions/send-push/) (needs the `FCM_SERVICE_ACCOUNT` secret). Google client IDs live in `lib/core/constants/google_config.dart`; `lib/firebase_options.dart` is FlutterFire-generated.

## Quality gates

- **CI** ([ci.yml](.github/workflows/ci.yml)): `flutter analyze` + `flutter test` on every PR and push to `main`.
- **Release** ([release-android.yml](.github/workflows/release-android.yml)): signed bundle to Google Play internal track.
- **Security**: row-level security on every table, column-level grants, private storage, RPC-only couple state changes. See [SECURITY.md](SECURITY.md).
- **Tests**: see [CONTRIBUTING.md](CONTRIBUTING.md#testing).

## How it was built (AI-assisted)

The project is developed with Claude Code, guided by a checked-in [CLAUDE.md](CLAUDE.md), project skills in [`.claude/skills/`](.claude/skills/), review subagents in [`.claude/agents/`](.claude/agents/), per-feature specs and ADRs. See [docs/AGENTIC_DEVELOPMENT.md](docs/AGENTIC_DEVELOPMENT.md).

## Repository map

```
lib/            app code (core, domain, data, presentation)
test/           unit and widget tests
supabase/       schema, migrations, edge functions
docs/           architecture, ADRs, feature specs, agentic workflow
.claude/        project skills, subagents, shared permissions
design/         HTML design reference
```
