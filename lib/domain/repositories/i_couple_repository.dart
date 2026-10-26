import '../entities/couple.dart';

abstract interface class ICoupleRepository {
  Future<String>  generateInviteCode(String userId);
  Future<Couple>  joinWithCode(String code, String userId);
  /// Emits once when someone joins with this user's invite code (the user becomes part of a couple).
  Stream<void>    watchPartnerJoined(String userId);
  Future<Couple>  getCouple(String coupleId);
  Stream<Couple>  watchCouple(String coupleId);
  /// Either partner can end the couple, no confirmation needed. Deletes everything
  /// the couple shared (moods, memories and their images, timeline, canvas, …).
  Future<void>    disconnect(String coupleId, String userId);
  Stream<bool>    watchPartnerPresence(String coupleId, String partnerUserId);
  Future<void>    updatePresence(String coupleId, String userId, {required bool isOnline});
}
