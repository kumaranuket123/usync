# Feature: Activity

A bottom-nav tab (route `/activity`, between Draw and Profile) that gathers the things a couple can do together. It replaced the Widgets tab.

## Screen: Activity (/activity)
A header ("Activity", "Things to do together") and three cards, each pushed over the shell:
- **Couple games** → `/games` (see `couple-games.md`)
- **Bucket list** → `/bucket-list` (see `bucket-list.md`)
- **Relationship timeline** → `/timeline` (see `timeline.md`)

Under the cards a **More coming soon** banner tells people more activities are on the way (not tappable).

These three used to be rows in Profile → YOUR CONNECTION; they are no longer listed there.

## Widgets (moved)
The home-screen widgets page is no longer a tab. It is opened from Profile → PREFERENCES → **Widgets** and is pushed over the shell (`/widgets`) with a back button.

## Code
- `lib/presentation/features/activity/screens/activity_screen.dart`
- Tab: `usync_bottom_nav.dart`; routes: `route_names.dart`, `app_router.dart`
- Test: `test/presentation/activity_screen_test.dart`
