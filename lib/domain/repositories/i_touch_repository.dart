abstract interface class ITouchRepository {
  Future<void> setTouchActive(String coupleId, String userId, {required bool isActive});
  Stream<bool> watchPartnerTouch(String coupleId, String partnerUserId);
  Future<void> registerDisconnectClear(String coupleId, String userId);
}
