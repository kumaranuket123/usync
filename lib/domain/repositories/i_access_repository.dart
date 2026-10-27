import '../entities/access.dart';
import '../entities/app_config.dart';

abstract interface class IAccessRepository {
  /// The server's switches. Never throws: with no connection it returns the last
  /// saved copy, or [AppConfig.open] if there is none, so a bad connection can
  /// never lock anyone out.
  Future<AppConfig> getConfig();

  /// Where the couple stands with the subscription. Never throws: with no
  /// connection it returns [Access.open].
  Future<Access> getAccess(String coupleId);
}
