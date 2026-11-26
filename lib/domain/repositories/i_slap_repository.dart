/// What one partner can give the other besides a slap.
enum Affection {
  hug('🤗', 'Hug'),
  kiss('💋', 'Kiss');

  const Affection(this.emoji, this.label);
  final String emoji, label;

  static Affection? fromKey(Object? key) {
    for (final a in values) {
      if (a.name == key) return a;
    }
    return null;
  }
}

abstract interface class ISlapRepository {
  /// Slaps the partner; they see it at once if they are in the game. Nothing is stored.
  Future<void> slap({required String coupleId, required String userId});

  /// The user ids of whoever slapped, as it happens. Includes only the partner's slaps.
  Stream<String> watchSlaps(String coupleId);

  /// Gives the partner a hug or a kiss; they see it at once if they are in the game. Nothing is stored.
  Future<void> give({required String coupleId, required String userId, required Affection affection});

  /// Hugs and kisses as they happen, with who gave them (the echo of your own is included).
  Stream<({String from, Affection affection})> watchAffection(String coupleId);
}
