import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

/// The notification list ("Moments"), kept on this phone. The server only carries a notification until the
/// recipient's phone has saved it (it needs the row to send the push), then the row is deleted.
///
/// One encrypted Hive box, one map per notification keyed by its id: `id`, `couple`, `type`, `body`, `at`
/// (milliseconds since epoch), `read` and `from`. The list is short (see [maxItems]), so it is read whole.
class NotificationLocalSource {
  NotificationLocalSource({required Box<dynamic> box}) : _box = box;

  final Box<dynamic> _box;

  static const maxItems = 50;

  final _changes = StreamController<void>.broadcast(sync: true);

  /// Fires after every change to the list.
  Stream<void> get changes => _changes.stream;

  bool has(String id) => _box.containsKey(id);

  /// Every saved notification of [coupleId], newest first.
  List<Map<String, dynamic>> all(String coupleId) {
    final list = [
      for (final v in _box.values)
        if (v is Map && v['couple'] == coupleId) Map<String, dynamic>.from(v),
    ]..sort((a, b) => (b['at'] as int).compareTo(a['at'] as int));
    return list;
  }

  Future<void> putAll(Iterable<Map<String, dynamic>> items) async {
    await _box.putAll({for (final m in items) m['id'] as String: m});
    _changes.add(null);
  }

  Future<void> delete(Iterable<String> ids) async {
    await _box.deleteAll(ids);
    _changes.add(null);
  }

  Future<void> markRead(String id) async {
    final m = _box.get(id);
    if (m is! Map || m['read'] == true) return;
    await _box.put(id, {...Map<String, dynamic>.from(m), 'read': true});
    _changes.add(null);
  }

  Future<void> markAllRead(String coupleId) async {
    final updates = <String, dynamic>{
      for (final m in all(coupleId))
        if (m['read'] != true) m['id'] as String: {...m, 'read': true},
    };
    if (updates.isEmpty) return;
    await _box.putAll(updates);
    _changes.add(null);
  }

  /// Sign-out, disconnect: nothing of this couple may stay on the phone.
  Future<void> clear() async {
    await _box.clear();
    _changes.add(null);
  }
}
