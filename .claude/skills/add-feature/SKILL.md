---
name: add-feature
description: Scaffold a new Usync feature following the clean-architecture layering (domain interface, data repository, BLoC, screen, DI, route, doc, test). Use when asked to add a feature or screen.
---

# Add a feature

Follow these steps in order; each maps to CLAUDE.md "Wiring a new feature".

1. **Domain**: entity in `lib/domain/entities/`, interface `I<Name>Repository` in `lib/domain/repositories/`. Pure Dart only.
2. **Data**: model in `lib/data/models/` (to/from entity), repository in `lib/data/repositories/` implementing the interface. Use `SupabaseClient` or an existing datasource; queue offline writes through `OutboxService` with client-generated ids.
3. **Backend**: if a table or RPC is needed, run the `add-supabase-migration` skill first.
4. **DI**: in `lib/core/di/injection.dart` register the repository as a lazy singleton bound to the interface and the BLoC as a **factory**.
5. **Presentation**: `lib/presentation/features/<name>/{bloc,screens}`. BLoC (events, states with Equatable) depends on the interface only. Screens get the BLoC via `GetIt.I<...>()` in a `BlocProvider`. Use theme tokens, not hard-coded colours.
6. **Route**: constant in `core/constants/route_names.dart`, route in `core/router/app_router.dart` (inside `ShellRoute` for main tabs).
7. **Docs**: run `write-feature-doc`.
8. **Test**: unit-test repository/service logic and BLoC with fakes under `test/`.
9. **Verify**: `flutter analyze` and `flutter test` must pass.
