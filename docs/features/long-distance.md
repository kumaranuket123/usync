# Feature: Long-distance card (distance + next meet)

A card on Home for couples whose [relationship mode](relationship-mode.md) is **Long-distance**: how far apart you are, and a shared countdown to the next time you meet. Couples who live together never see it, and it takes no space on their Home.

---

## The card

One tappable line under the quick actions, e.g. `✈️ 420 km apart  ·  Meet in 12 days`.

| Part | Shows | When it is missing |
|---|---|---|
| Distance | Great-circle distance between the two saved locations (`GeoUtil.formatDistance`: `850 m`, `4.2 km`, `420 km`) | Left out until **both** partners have shared a location (see [location](location.md)) |
| Next meet | `Meet in N days`, `We meet tomorrow`, `We meet today 🎉` | `Set our next meet`; a date in the past counts as not set |

Tapping opens a bottom sheet: **Choose date** / **Change date** (date picker from today up to 3 years ahead) and **Remove date**. Either partner can set or clear it; the other sees it live. Setting a date sends the partner a `milestone` notification ("<name> set your next meet for Dec 12 ✈️"); clearing it does not.

## Behaviour

- `LongDistanceBloc` loads the couple, watches the couple row (so a mode or date change on the partner's phone shows at once) and the partner's location row; our own row is read once. The card hides itself if the couple cannot be read.
- It lives in the Home column, which is not scrollable, so the card is compact. In long-distance mode check Home on small phones for overflow.
- The distance only uses the last saved locations (refreshed when the app opens, see [location](location.md)), so it can be a little behind.
- No reminder is sent for the date itself yet.

## Data

`couples.next_meet_on` (date, nullable), set only through the RPC `set_next_meet(p_couple, p_day)` (active members only; null clears; a day before yesterday UTC is refused). `disconnect_couple` and `delete_my_account` clear it with the rest of what the couple shared. Migration: `supabase/migrations/next_meet.sql`.

## Code

`Couple.nextMeetOn`, `ICoupleRepository.setNextMeet`, `GeoUtil` (`core/utils/geo_util.dart`), `LongDistanceBloc`, `LongDistanceCard` (`presentation/features/long_distance/`).
