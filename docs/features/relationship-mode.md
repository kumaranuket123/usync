# Feature: Relationship Mode

A per-couple setting, **Together** or **Long-distance**, that both partners share. It lets the app tailor content to how the couple actually lives. It is the base for the Phase 2 mode-specific features; today it picks the question-of-the-day bank.

---

## Setting it

Profile -> YOUR CONNECTION -> **Relationship type** row (shows the current mode). Tapping it opens a bottom sheet with the two options (🏡 Together, ✈️ Long-distance, current one ticked). Either partner can change it at any time; there is no confirmation. The new default for every couple is Together.

The row sits in `ProfileScreen`. `ProfileBloc` handles `RelationshipModeChanged`, calls `ICoupleRepository.setRelationshipMode`, and shows the saved value (the couple stream also delivers it, so the partner's open Profile updates live).

## What it changes today

- **Question of the day** uses a bank per mode: the shared questions plus 10 mode-specific ones (`DailyQuestion.bankFor(mode)`). `QuestionBloc` reads the mode with `ICoupleRepository.getRelationshipMode`, which asks the server instead of the few-minute memory copy, so both partners get the same question right after a change. If the mode cannot be read (offline, nothing saved) it falls back to Together.
- If the mode changes after one partner already answered today, the other partner may see a different question for the rest of that day. The answers are still stored per day.

- **Long-distance** couples get the Home card with the distance and a shared next-meet countdown ([long-distance](long-distance.md)); Together couples do not see it.

## Data

`couples.relationship_mode` (`'together'` | `'long_distance'`, default `'together'`), set only through the RPC `set_relationship_mode(p_couple, p_mode)` (security definer, active couple members only, rejects any other value). Migration: `supabase/migrations/relationship_mode.sql`.

## Code

`RelationshipMode` (in `domain/entities/couple.dart`, with emoji/label/description), `Couple.relationshipMode`, `CoupleModel`, `ICoupleRepository.getRelationshipMode` / `setRelationshipMode`, `ProfileBloc`, `QuestionBloc`.

## Next (Phase 2)

Together: date ideas. (The shared [bucket list](bucket-list.md) is for every couple.)
