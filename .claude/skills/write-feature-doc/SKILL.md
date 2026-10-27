---
name: write-feature-doc
description: Write or update docs/features/<feature>.md in the project's spec format. Use after adding or changing a feature.
---

# Write a feature doc

Read an existing spec (e.g. `docs/features/canvas.md`) and match its structure:

1. One-paragraph summary of the feature.
2. **Screens**: route, layout, widgets, gestures.
3. **State**: BLoC events and states.
4. **Data**: tables, RPCs, Realtime events, storage paths involved, and which are durable vs ephemeral.
5. **Edge cases**: offline, partner absent, permissions denied.

Read the code before writing; document what exists, not what is planned. Link the doc from the README feature table.
