# ADR 0002: Clean architecture with BLoC and GetIt

Status: accepted

**Context.** Several features (canvas, touch, location, memories) mix realtime streams, persistence and UI. Testing and replacing data sources must stay cheap.

**Decision.** Three layers (domain / data / presentation) with `I*Repository` interfaces in domain. BLoC for state. GetIt for DI: repositories are lazy singletons bound to interfaces, BLoCs are factories.

**Consequences.** BLoCs are testable with fakes; data sources can change (as in the Firebase -> Supabase move) without touching presentation. Cost: boilerplate per feature, mitigated by the `add-feature` project skill.
