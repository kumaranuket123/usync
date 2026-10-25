/// Remembers signed storage links until shortly before they stop working, so
/// a list that changes often only signs what is actually new.
class SignedUrlCache {
  SignedUrlCache({
    this.lifetime    = const Duration(hours: 1),
    this.renewBefore = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// How long the server's links last.
  final Duration lifetime;
  /// A link this close to expiring is signed again.
  final Duration renewBefore;
  final DateTime Function() _now;

  final _links = <String, ({String url, DateTime expiresAt})>{};

  /// Links for [paths]. [sign] is asked only for the ones missing or about to
  /// expire, and returns path -> url for them (a path it cannot sign is left out).
  Future<Map<String, String>> resolve(
    Iterable<String> paths,
    Future<Map<String, String>> Function(List<String> missing) sign,
  ) async {
    final wanted = paths.toSet();
    if (wanted.isEmpty) return {};

    final now     = _now();
    final renewAt = now.add(renewBefore);
    final missing = [
      for (final p in wanted)
        if ((_links[p]?.expiresAt ?? now).isBefore(renewAt)) p,
    ];

    if (missing.isNotEmpty) {
      final signed    = await sign(missing);
      final expiresAt = now.add(lifetime);
      signed.forEach((path, url) => _links[path] = (url: url, expiresAt: expiresAt));
    }
    return {
      for (final p in wanted)
        if (_links[p] != null) p: _links[p]!.url,
    };
  }

  void clear() => _links.clear();
}
