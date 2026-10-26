/// Keeps loaded values for a while and shares a load already in progress, so
/// asking for the same thing from several places at once costs one request.
/// Failures are never kept: the next call tries again.
class TtlCache<T> {
  TtlCache({required this.ttl, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;

  final _values   = <String, ({T value, DateTime loadedAt})>{};
  final _inflight = <String, Future<T>>{};

  /// The cached value if it is still fresh, otherwise the result of [load].
  Future<T> get(String key, Future<T> Function() load) {
    final hit = _values[key];
    if (hit != null && _now().difference(hit.loadedAt) < ttl) return Future.value(hit.value);

    return _inflight[key] ??= load().then((value) {
      _values[key] = (value: value, loadedAt: _now());
      return value;
    }).whenComplete(() {
      // A block body on purpose: an arrow would return the removed future, which
      // whenComplete then waits for, and that future is this one.
      _inflight.remove(key);
    });
  }

  /// Stores a value we just learned some other way (e.g. a live update).
  void put(String key, T value) => _values[key] = (value: value, loadedAt: _now());

  void invalidate(String key) => _values.remove(key);

  void clear() {
    _values.clear();
    _inflight.clear();
  }
}
