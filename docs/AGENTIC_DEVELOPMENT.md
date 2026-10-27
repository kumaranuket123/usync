# Agentic development

How this repo is set up so an AI coding agent (Claude Code) can work in it safely and consistently, and so a human reviewer can verify the result.

## 1. Context the agent reads first

| Artifact | Purpose |
|---|---|
| [CLAUDE.md](../CLAUDE.md) | Commands, architecture, wiring checklist, auth/routing, data split, theming. Loaded every session. |
| [docs/ARCHITECTURE.md](ARCHITECTURE.md) | Layer rules and data-flow diagrams. |
| [docs/adr/](adr/) | Why key decisions were made, so the agent does not re-litigate them. |
| [docs/features/](features/) | Per-feature specs: screens, state, data. |
| `design/index.html` | Visual reference. |

## 2. Project skills (`.claude/skills/`)

Repeatable procedures the agent invokes instead of improvising.

| Skill | Encodes |
|---|---|
| `add-feature` | Domain interface -> data repo -> migration -> DI (singleton/factory) -> BLoC/screen -> route -> doc -> test -> verify. |
| `add-supabase-migration` | Inspect schema, RLS on every table, column grants, definer RPCs, FK indexes, run advisors. |
| `write-feature-doc` | Spec format for `docs/features/`. |

## 3. Review subagents (`.claude/agents/`)

| Agent | Checks |
|---|---|
| `architecture-reviewer` | Layer boundaries, DI registration, theme tokens, tests and docs present. |
| `rls-security-reviewer` | Policies, grants, `SECURITY DEFINER`, storage and realtime access. Read-only. |

Both are read-only (no Edit/Write) so review is independent of implementation.

## 4. Guardrails

- `.claude/settings.json` pre-approves only safe read/verify commands (`analyze`, `test`, `git status/diff/log`).
- CI (`.github/workflows/ci.yml`) runs `flutter analyze` + `flutter test` on every PR and push, so agent output is gated the same as human output.
- Security is enforced in the database (ADR 0003), so a mistake in client code cannot expose another couple's data.
- Backend changes are applied as migrations and checked with Supabase security/performance advisors.

## 5. Intended loop

1. Agent reads CLAUDE.md and the relevant feature spec.
2. Runs the matching skill (`add-feature`, `add-supabase-migration`).
3. Implements in small steps, runs `flutter analyze` and `flutter test`.
4. Runs `architecture-reviewer` (and `rls-security-reviewer` for SQL) on the diff.
5. Updates the feature doc; commits one logical change with a clear message.

## 6. Evidence in the repo

- Git history shows incremental, single-purpose commits: backend migration (Firebase -> Supabase), realtime canvas, offline support, security hardening, home-screen widget.
- 18 migrations in `supabase/migrations/` document each schema/policy change, including `security_hardening.sql` and `perf_tuning.sql` driven by advisor output.
- 90 tests in `test/` cover the infrastructure (outbox, caches, error mapping, realtime channel), BLoCs (pairing, mood, settings) and repositories (couple, mood) plus models.
