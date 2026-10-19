import 'package:firebase_database/firebase_database.dart';

class RtdbSource {
  RtdbSource({required this.database});
  final FirebaseDatabase database;

  // ── Membership (gates all other RTDB paths via database.rules.json) ──
  DatabaseReference membersRef(String coupleId) =>
      database.ref('members/$coupleId');

  // ── Presence ──────────────────────────────────────────────────
  DatabaseReference presenceRef(String coupleId, String userId) =>
      database.ref('presence/$coupleId/$userId');

  // ── Mood (current) ────────────────────────────────────────────
  DatabaseReference currentMoodRef(String coupleId, String userId) =>
      database.ref('mood/$coupleId/$userId/current');

  // ── Canvas ────────────────────────────────────────────────────
  DatabaseReference canvasRef(String coupleId) =>
      database.ref('canvas/$coupleId');

  DatabaseReference strokeRef(String coupleId, String strokeId) =>
      database.ref('canvas/$coupleId/strokes/$strokeId');

  DatabaseReference strokePointsRef(String coupleId, String strokeId) =>
      database.ref('canvas/$coupleId/strokes/$strokeId/points');

  DatabaseReference canvasClearedRef(String coupleId) =>
      database.ref('canvas/$coupleId/clearedAt');

  // ── Touch ─────────────────────────────────────────────────────
  DatabaseReference touchRef(String coupleId, String userId) =>
      database.ref('touch/$coupleId/$userId');
}
