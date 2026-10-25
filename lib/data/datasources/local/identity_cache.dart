import '../../../core/utils/ttl_cache.dart';
import '../../../domain/entities/couple.dart';
import '../../../domain/entities/user.dart';

/// Who you are, who your partner is and your couple, kept in memory for a few
/// minutes. Almost every screen needs these, and they rarely change, so
/// without this each screen opened would ask the server for them again.
class IdentityCache {
  final profiles = TtlCache<AppUser>(ttl: const Duration(minutes: 10));
  final couples  = TtlCache<Couple>(ttl: const Duration(minutes: 5));

  /// Pairing and disconnecting change the couple and both profiles.
  void clear() {
    profiles.clear();
    couples.clear();
  }
}
