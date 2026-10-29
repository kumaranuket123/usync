/// The words that tell people how their data is protected. One place, so the welcome slide, the
/// login screen, the Home badge, the sheet and About never say different things.
///
/// Keep it true: it matches `docs/security.md` and `docs/privacy-policy.html`.
abstract final class TrustCopy {
  static const headline = 'Private by design';

  /// One sentence for the welcome slide and the login screen.
  static const summary =
      'Your moods, drawings, memories and location are encrypted on your phone. Only you and your partner can read them.';

  static const promise = 'No ads, no analytics, and we never sell your data.';

  /// Content that only the two partners can read.
  static const encrypted = [
    'Moods and your daily answers',
    'Bucket list and next-meet date',
    'Shared drawings, memories and pictures',
    'Your location',
    'Timeline dates',
    'The details of your notifications',
  ];

  /// Honest limits: what encryption does not hide.
  static const stillVisible = [
    'That you two are paired, and when and how often things are shared',
    'Streaks and counts, and the kind of activity (for example "a mood")',
    'Your name and email from Google, your avatar and your relationship type',
  ];

  /// Services that handle data on our behalf.
  static const services = [
    'Supabase stores your account and your encrypted data.',
    'Google handles sign-in and delivers push notifications.',
    'OpenStreetMap draws the map on the location screen (it sees the area you view).',
  ];
}
