# ADR 0004: Ephemeral state on Realtime, durable state in Postgres

Status: accepted

**Decision.** Presence (online), touch events and in-progress stroke chunks go over one private Realtime channel per couple. Only finished strokes, moods, memories, etc. are written to Postgres.

**Consequences.** Low latency and no write amplification for drawing. Trade-off: no `onDisconnect`, so touch end is inferred from Presence leave.
