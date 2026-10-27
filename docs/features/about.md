# Feature: About Usync

An in-app page that explains what Usync is and lists everything it can do, in plain language. Opened from Settings -> ABOUT -> **About Usync** (`/about`, pushed over the shell, no bottom nav).

---

## Screen: AboutScreen

- Header: back button and "About Usync".
- Hero card: 💞, "Usync", the installed version (`package_info_plus`, same source as Settings) and a short description.
- Five sections of feature cards (emoji, title, one or two sentences):
  - **CONNECT**: pairing, touch sync, moods, question of the day.
  - **CREATE AND REMEMBER**: shared canvas, memories, timeline, bucket list, streaks.
  - **NEAR OR FAR**: relationship type, long-distance card, location.
  - **ALWAYS WITH YOU**: notifications, home-screen widget, offline support, themes.
  - **PRIVATE BY DESIGN**: app lock, only the two of you, deleting your data.
- Footer row **Read our Privacy Policy**, which opens the hosted policy in the browser (`openPrivacyPolicy`, shared with the Settings row).

The page is one scrollable column, so it works at any size and text scale (covered by `test/presentation/about_screen_test.dart`, which also checks every feature is listed).

## Keeping it true

The content is the `_sections` list in `about_screen.dart`. When a user-facing feature is added, changed or removed, update that list (and the matching text in [privacy-policy.html](../privacy-policy.html) if data handling changes).

## Code

`AboutScreen` (`presentation/features/settings/screens/about_screen.dart`), `RouteNames.about`, `openPrivacyPolicy` (`core/utils/privacy_policy.dart`).
