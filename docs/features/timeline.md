# Feature: Timeline

"Our Journey": a vertical timeline of the couple's shared story. It shows milestones the server records on its own (connecting, first doodle, streaks, shared moments) and **special dates** that either partner adds: a first date, a trip, a proposal, the ring ceremony, a wedding day. Both partners are reminded on the day, and every year if the date repeats, so neither has to be the one who remembers. A synthetic "Today · Day N" card closes the list.

---

## Screens

### TimelineScreen (`/timeline`)

Pushed from Profile → "Relationship Timeline". Not a bottom-nav destination; no bottom nav.

1. Header: back button, "Our Journey", "N days together" (from the couple's `daysTogether`), and an **Add date** button.
2. A gradient line (pink → purple → cyan) behind a list of dots and glass cards, in date order. Later dates are upcoming and sit below "Today".
3. If there are no custom dates, a hint card under "Today": "Add the days that matter: when you first met, your first date, an engagement. You both get a notification on the day."

**Cards.** Each has an emoji dot, a title, an optional note and the date. Custom dates also show:
- "· every year" after the date when they repeat;
- a countdown: "Today 🎉", "In N days", or for yearly dates "Next in N days" (nothing for a one-off date already past);
- a trash icon, which asks "Delete this date?" before deleting. Either partner can delete.

Automatic milestones use their type's emoji (🎉 connected, ✏️ first doodle, 🔥 7-day, 🌙 30-day, 💫 100-day, 💖 100 moments) and have no delete icon.

### Add a special date (bottom sheet)

Opened by **Add date**.

| Field | Details |
|---|---|
| What happened | Required title, up to 60 characters (hint "Our first date") |
| Date | Date picker, defaults to today, 1990 to 30 years ahead |
| Icon | 💞 🥂 💍 🎉 ✈️ 🌹 🎂 🏡 ✨ (first is selected) |
| Note | Optional, up to 140 characters |
| Celebrate every year | Switch, **on by default**: "Notify you both on this day each year" |

**Save date** closes the sheet and adds the date. Messages use `appSnackBar`.

---

## State

`TimelineBloc` (factory in `injection.dart`), provided in the screen subtree.

**Events:** `TimelineLoaded(coupleId)`, `DateAdded(title, date, note, emoji, repeatsYearly)` (calendar day only, time ignored), `DateDeleted(id)`.

**States:** `TimelineLoading`, `TimelineReady(milestones, daysTogether, notice)`, `TimelineEmpty(daysTogether)` (no couple), `TimelineError(message)`. `notice` is a one-off message the screen shows in a snackbar.

**Load:** read the couple (day count) and the milestones, add any dates still waiting to be sent, add the synthetic "today" item, sort by date, emit. Reminders are rescheduled in the background (`unawaited`, failures are only logged). Add and delete reload the list afterwards.

The list is loaded when the screen opens and after the user's own changes. It is **not live**: a date the partner adds appears on the next open of the screen.

---

## Data

### Durable (Postgres `milestones`, RLS by couple)

| Column | Notes |
|---|---|
| `type` | `firstConnect`, `firstDoodle`, `streak7`, `streak30`, `streak100`, `moments100` (written by the server) or `custom` (written by a partner) |
| `title`, `note`, `occurred_at` | For custom dates these hold placeholders only: `🔒`, and 1 Jan 1970 12:00 UTC |
| `emoji`, `repeats_yearly`, `created_by` | Added by `timeline_dates.sql`. A sealed date writes `repeats_yearly = false` and no emoji; the real values are only in `enc` |
| `enc` | The real title, note, emoji, day and yearly flag, **sealed on the phone** with the couple key (`e2ee_timeline.sql`) |

Custom dates are written straight to the table by either partner (`milestones_write` policy); there is no RPC. Automatic milestones stay readable. Older readable custom dates are still shown and are sealed later by the legacy sealer (`docs/security.md`, E5a).

When a date is added, the partner also gets an immediate notification ("<name> added a date to your timeline 🕰️"), separate from the reminders on the day.

`IMilestoneRepository`: `getMilestones`, `addDate` (returns `sentNow` and the milestone), `deleteMilestone`.

### Reminders

Reminders are **local notifications scheduled by each phone** (`ReminderService`, `flutter_local_notifications`), not server pushes, because the server can no longer read the dates.

- Time: 9:00 local. A one-off date reminds on its day; a yearly date for its next three anniversaries, each with its own count. 29 February falls on the 28th in other years.
- Only custom dates are reminders. iOS keeps at most 64 pending notifications.
- Rescheduled when the timeline loads or changes, and on app start and return to the foreground (`ReminderSync`, set up in `main.dart`), so a partner who never opens the timeline still gets them.
- Cleared on sign-out, disconnect and account deletion. The text is built on the phone and never leaves it.

`supabase/migrations/timeline_dates.sql` also defines a daily server job (`send_milestone_reminders`, 03:30 UTC) that inserts `milestone` notifications for both partners. `remove_milestone_reminders.sql` retires it at release; check that migration's status before relying on either path alone.

---

## Edge cases

- **Offline:** the last copy of the list is shown from the session cache (kept sealed). A date added offline is queued in the outbox (`OutboxService`), shown meanwhile, and sent when back online ("Saved on this device. It will be sent when you are back online."). Delete offline fails with "Could not delete this date. Check your connection."
- **Encryption not ready:** adding is refused with the encryption message (no key yet, never stored readable). Other save failures show "Could not save this date".
- **Locked dates:** a date this phone cannot open yet (the key has not arrived) shows as "Locked until your key arrives" and gets no reminder.
- **No couple:** `TimelineEmpty`, nothing to show.
- **Partner absent:** nothing is needed from them. They see the date on their next open and are reminded by their own phone.
- **Time zones:** the chosen day is saved as noon UTC (inside the sealed value), so it shows as the same calendar day in time zones from UTC-12 to UTC+11.
