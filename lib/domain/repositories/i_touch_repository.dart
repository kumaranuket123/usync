abstract interface class ITouchRepository {
  Future<void> setTouchActive(String coupleId, String userId, {required bool isActive});
  Stream<bool> watchPartnerTouch(String coupleId, String partnerUserId);
  /// Announces us on Presence as being on the touch screen.
  Future<void> registerDisconnectClear(String coupleId, String userId);
  /// Back to plain Presence once we leave the touch screen.
  Future<void> leaveTouchScreen(String coupleId, String userId);
  /// If the partner is not on the touch screen to feel it, sends them a push
  /// ("wants to feel you"). Rate-limited so holding or re-tapping does not spam.
  Future<void> notifyIfPartnerAway(String coupleId, String userId, String partnerUserId);
}
