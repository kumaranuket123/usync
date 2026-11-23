abstract interface class ISlapRepository {
  /// Slaps the partner; they see it at once if they are in the game. Nothing is stored.
  Future<void> slap({required String coupleId, required String userId});

  /// The user ids of whoever slapped, as it happens. Includes only the partner's slaps.
  Stream<String> watchSlaps(String coupleId);
}
