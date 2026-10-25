import '../entities/couple.dart';

abstract interface class ICoupleRepository {
  Future<String>  generateInviteCode(String userId);
  Future<Couple>  joinWithCode(String code, String userId);
  Future<Couple>  getCouple(String coupleId);
  Stream<Couple>  watchCouple(String coupleId);
  /// Disconnecting needs both partners: one requests, the other confirms.
  Future<void>    requestDisconnect(String coupleId, String userId);
  /// Withdraws your own request or declines the partner's.
  Future<void>    cancelDisconnect(String coupleId);
  Future<void>    confirmDisconnect(String coupleId, String userId);
  Stream<bool>    watchPartnerPresence(String coupleId, String partnerUserId);
  Future<void>    updatePresence(String coupleId, String userId, {required bool isOnline});
}
