# Feature: Mood insights

A calm look back at how in sync the two of you have been this week, built from the moods you already share. It adds no new data, no migration and no backend change: it only reads the `moods` table.

---

## Screen: MoodInsightsScreen (`/mood-insights`)

Opened from Profile -> YOUR CONNECTION -> **Mood insights**. Pushed over the shell (no bottom nav).

- **IN SYNC card**: "N of the last 7 days" with one sentence ("No in-sync days yet…", "On N days you both felt alike 💞", or "Every single day…").
- **Week strip**: seven columns, oldest first, ending today. Each shows the weekday letter, your mood emoji (top), your partner's (bottom) and a 💞 on in-sync days. A day with no mood shows a dot.
- **Most shared**: the mood each of you shared most often this week.
- **Empty state** when nobody shared a mood in the window: "Share a mood to start seeing insights."
- **Error state** with **Try again** when the moods cannot be loaded (insights need a connection).
- A footnote explains the UTC days and the mood groups.

## Rules

- **Day** = UTC day, the same boundary the day streak uses (`supabase/migrations/streaks.sql`), so partners in different time zones are compared on the same day. A mood sent late in the evening locally can fall on the next UTC day.
- A person's mood **for a day** = the last mood they shared that day.
- **Mood groups** (`MoodType.group`): warm = happy, thinking about you, missing you; calm = sleeping, relaxing; busy = busy. A custom mood has no group and only matches another custom mood with the same text (ignoring case and spaces).
- **In sync** = both shared a mood that day and `Mood.feelsLike` is true (same group, or same custom text).
- **Most shared** counts every mood in the window (not just the last of each day); on a tie the most recent wins. Custom moods are counted by their text.
- Moods outside the 7-day window, or in the future, are ignored.

## Code

- `MoodGroup`, `MoodType.group`, `Mood.feelsLike`, `Mood.countKey` (`domain/entities/mood.dart`).
- `MoodDay`, `MoodInsights.compute` (`domain/entities/mood_insights.dart`): a pure function, fully unit-tested.
- `IMoodRepository.getMoodsSince(coupleId, since)` / `MoodRepository`: one query, `couple_id = ?`, `sent_at >= since`, oldest first, limit 500 (served by the existing `(couple_id, sent_at desc)` index).
- `MoodInsightsBloc` (loads the week and the partner's name; falls back to "Your partner"), `MoodInsightsScreen`, `MoodInsightsView` (`presentation/features/mood_insights/`).

## Not included

Longer ranges (month, year), charts, and anything beyond moods (touch, canvas or question activity).
