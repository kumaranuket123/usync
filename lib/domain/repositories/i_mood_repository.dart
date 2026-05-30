import '../entities/mood.dart';

abstract interface class IMoodRepository {
  Future<void>    sendMood(String coupleId, String userId, MoodType type);
  Stream<Mood?>   watchPartnerMood(String coupleId, String partnerUserId);
  Future<List<Mood>> getMoodHistory(String coupleId, {int limit = 10});
  Future<Mood?>   getLastSentMood(String userId);
}
