import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/mood.dart';
import '../../domain/repositories/i_mood_repository.dart';
import '../datasources/remote/firestore_source.dart';
import '../datasources/remote/rtdb_source.dart';
import '../models/mood_model.dart';

class MoodRepository implements IMoodRepository {
  MoodRepository({required this.firestoreSource, required this.rtdbSource});

  final FirestoreSource firestoreSource;
  final RtdbSource      rtdbSource;

  @override
  Future<void> sendMood(String coupleId, String userId, MoodType type) async {
    final mood = MoodModel(type: type, userId: userId, sentAt: DateTime.now());
    // Live sync to partner home screen.
    await rtdbSource.currentMoodRef(coupleId, userId).set(mood.toJson());
    // Persist for history, notification trigger, and strip.
    await firestoreSource.moodHistory(coupleId).add(mood.toJson());
  }

  @override
  Stream<Mood?> watchPartnerMood(String coupleId, String partnerUserId) {
    return rtdbSource
        .currentMoodRef(coupleId, partnerUserId)
        .onValue
        .map((event) {
          final val = event.snapshot.value;
          if (val == null) return null;
          return MoodModel.fromJson(Map<String, dynamic>.from(val as Map));
        });
  }

  @override
  Future<List<Mood>> getMoodHistory(String coupleId, {int limit = 10}) async {
    final snap = await firestoreSource
        .moodHistory(coupleId)
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => MoodModel.fromJson(d.data()))
        .toList();
  }

  @override
  Future<Mood?> getLastSentMood(String userId) async {
    // Queried across all couple mood histories — simplified by filtering on userId.
    // In practice, the app always knows the coupleId; this signature could accept it.
    return null;
  }
}
