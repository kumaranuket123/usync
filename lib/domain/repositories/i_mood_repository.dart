import '../entities/mood.dart';

abstract interface class IMoodRepository {
  /// For [MoodType.custom], [custom] supplies the text and emoji.
  Future<void>    sendMood(String coupleId, String userId, MoodType type, {CustomMood? custom});
  Stream<Mood?>   watchPartnerMood(String coupleId, String partnerUserId);
  Future<List<Mood>> getMoodHistory(String coupleId, {int limit = 10});
  Future<Mood?>   getLastSentMood(String userId);
  /// The user's own custom moods, most recent first, without repeats.
  Future<List<CustomMood>> getMyCustomMoods(String userId, {int limit = 6});
}
