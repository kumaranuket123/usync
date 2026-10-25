import '../entities/mood.dart';

abstract interface class IMoodRepository {
  /// For [MoodType.custom], [custom] supplies the text and emoji. Returns true
  /// when it reached the server, false when it was saved on the device to be
  /// sent once there is a connection.
  Future<bool>    sendMood(String coupleId, String userId, MoodType type, {CustomMood? custom});
  /// The couple's most recent moods (both partners), newest first. Emits the
  /// copy saved on the device straight away, then live updates. One stream
  /// serves both "recent moods" and "the partner's current mood".
  Stream<List<Mood>> watchRecentMoods(String coupleId);
  Future<Mood?>   getLastSentMood(String userId);
  /// The user's own custom moods, most recent first, without repeats.
  Future<List<CustomMood>> getMyCustomMoods(String userId, {int limit = 6});
}
