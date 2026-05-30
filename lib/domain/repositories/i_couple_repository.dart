import '../entities/couple.dart';

abstract interface class ICoupleRepository {
  Future<String>  generateInviteCode(String userId);
  Future<Couple>  joinWithCode(String code, String userId);
  Future<Couple>  getCouple(String coupleId);
  Stream<bool>    watchPartnerPresence(String coupleId, String partnerUserId);
  Future<void>    updatePresence(String coupleId, String userId, {required bool isOnline});
}
