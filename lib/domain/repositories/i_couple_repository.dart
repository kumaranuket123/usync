import '../entities/couple.dart';

abstract interface class ICoupleRepository {
  Future<String>  generateInviteCode(String userId);
  Future<Couple>  joinWithCode(String code, String userId);
  /// Emits once when someone joins with this user's invite code (the user becomes part of a couple).
  Stream<void>    watchPartnerJoined(String userId);
  Future<Couple>  getCouple(String coupleId);
  Stream<Couple>  watchCouple(String coupleId);
  /// The couple's relationship mode, read from the server (not the few-minute
  /// memory copy) so both partners agree right after one of them changes it.
  /// Offline, the last saved copy is used.
  Future<RelationshipMode> getRelationshipMode(String coupleId);
  /// Either partner can change it at any time; the other sees it through [watchCouple].
  Future<void>    setRelationshipMode(String coupleId, RelationshipMode mode);
  /// Sets (or, with a null [day], clears) the couple's next meeting and tells the
  /// partner. Either partner can do it; the other sees it through [watchCouple].
  Future<void>    setNextMeet(String coupleId, String userId, DateTime? day);
  /// Either partner can end the couple, no confirmation needed. Deletes everything
  /// the couple shared (moods, memories and their images, timeline, canvas, …).
  Future<void>    disconnect(String coupleId, String userId);
  Stream<bool>    watchPartnerPresence(String coupleId, String partnerUserId);
  Future<void>    updatePresence(String coupleId, String userId, {required bool isOnline});
}
