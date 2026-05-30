import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreSource {
  FirestoreSource({required this.firestore});
  final FirebaseFirestore firestore;

  // ── Users ──────────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get users => firestore.collection('users');
  DocumentReference<Map<String, dynamic>>  userDoc(String uid) => users.doc(uid);

  // ── Couples ───────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get couples => firestore.collection('couples');
  DocumentReference<Map<String, dynamic>>  coupleDoc(String id) => couples.doc(id);

  // ── Invite codes ──────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get inviteCodes => firestore.collection('inviteCodes');

  // ── Moods ─────────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> moodHistory(String coupleId) =>
      firestore.collection('moods').doc(coupleId).collection('history');

  // ── Memories ──────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> memoryItems(String coupleId) =>
      firestore.collection('memories').doc(coupleId).collection('items');

  DocumentReference<Map<String, dynamic>> memoryDoc(String coupleId, String id) =>
      memoryItems(coupleId).doc(id);

  // ── Milestones ────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> milestoneEvents(String coupleId) =>
      firestore.collection('milestones').doc(coupleId).collection('events');

  // ── Notifications ─────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> notifItems(String coupleId) =>
      firestore.collection('notifications').doc(coupleId).collection('items');

  DocumentReference<Map<String, dynamic>> notifDoc(String coupleId, String id) =>
      notifItems(coupleId).doc(id);
}
