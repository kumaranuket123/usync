abstract final class AppConstants {
  // ── Pairing ───────────────────────────────────────────────────
  static const int inviteCodeLength  = 4;
  static const int inviteCodeTtlHrs  = 24;

  // ── Streaks ───────────────────────────────────────────────────
  static const int streakMilestone1  = 7;
  static const int streakMilestone2  = 30;
  static const int streakMilestone3  = 100;

  // ── Moments ───────────────────────────────────────────────────
  static const int momentsMilestone1 = 100;

  // ── Canvas ────────────────────────────────────────────────────
  static const double penWidth       = 3.0;
  static const double eraserWidth    = 30.0;

  // ── Notifications ─────────────────────────────────────────────
  static const int  notifQueryLimit  = 50;

  // ── Moods ─────────────────────────────────────────────────────
  static const int  moodHistoryLimit = 10;

  // ── Memories ──────────────────────────────────────────────────
  static const String canvasBitmapPath = 'canvas-memories';

  // ── Particles ─────────────────────────────────────────────────
  static const int splashParticleCount = 40;
  static const int authParticleCount   = 20;

  // ── Touch ─────────────────────────────────────────────────────
  static const int hapticRepeatMs    = 1200;
}
