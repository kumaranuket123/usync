import 'dart:async';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

/// The chat history, kept on this phone (the server only carries a message until the partner's phone has
/// it). Three Hive boxes, all encrypted with the phone's local key:
///  * [messages] (lazy): one map per message, keyed by its send time in microseconds written as a
///    zero-padded string (Hive integer keys stop at 32 bits), so a page of the chat is a slice of the
///    sorted keys and only that page is read from disk;
///  * [index] (in memory): message id -> {k: key, u: unread, e: expiry}, small enough to scan; also holds
///    which account owns the history;
///  * [media] (lazy): the decrypted photo / voice bytes by message id (protected by the box encryption).
///
/// A message is a plain map; see ChatMessageModel. Keys used here: `id`, `at` (microseconds), `mine`,
/// `seen` and `exp`.
class ChatLocalSource {
  ChatLocalSource({required LazyBox<dynamic> messages, required Box<dynamic> index, required LazyBox<dynamic> media})
      : _messages = messages,
        _index = index,
        _media = media;

  final LazyBox<dynamic> _messages;
  final Box<dynamic>     _index;
  final LazyBox<dynamic> _media;

  static const _ownerKey = '_owner';

  final _changes = StreamController<void>.broadcast(sync: true);
  /// Fires after every change to the history.
  Stream<void> get changes => _changes.stream;

  List<String>? _sorted;

  /// Writes run one at a time, so a read-modify-write cannot lose or resurrect a message.
  Future<void> _tail = Future.value();
  Future<T> _locked<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  static const _tombPrefix = '_t:';
  static const _tombLife = Duration(days: 15);

  static String _keyFor(int micros) => micros.toString().padLeft(20, '0');

  // ── Ownership ────────────────────────────────────────────────────────────

  /// Who this history belongs to (`userId:coupleId`), or null for a fresh phone.
  String? get owner => _index.get(_ownerKey) as String?;

  /// Makes this history belong to [who]; the history of anyone else is thrown away first. Returns true when
  /// the history was new or reset (first run, or another account), so the caller can import what the
  /// server still holds of the user's own messages.
  Future<bool> claim(String who) async {
    if (owner == who && await _consistent()) return false;
    await clear();
    await _index.put(_ownerKey, who);
    return true;
  }

  /// Forgets everything, the owner too (sign-out: nothing of this account may stay on the phone).
  Future<void> reset() async {
    await clear();
    await _index.delete(_ownerKey);
  }

  /// The three boxes are recovered independently when one cannot be opened; if what is in them no longer
  /// agrees (an index entry without its message, or the other way round) nothing can be trusted.
  Future<bool> _consistent() async => _messages.length == _entries.length;

  /// Remembers that [id] was here, so a copy of it still on the server (a failed collect, a stale
  /// snapshot) is not saved again after it was deleted, or before a "delete for everyone" arrives.
  Future<void> _tombstone(String id) => _index.put('$_tombPrefix$id', DateTime.now().toUtc().microsecondsSinceEpoch);

  Future<void> forget(Iterable<String> ids) => _locked(() async {
        for (final id in ids) {
          await _tombstone(id);
        }
      });

  /// Was saved here at some point (and may since have been deleted).
  bool knows(String id) => _index.containsKey(id) || _index.containsKey('$_tombPrefix$id');

  Future<void> _dropOldTombstones() async {
    final cutoff = DateTime.now().toUtc().subtract(_tombLife).microsecondsSinceEpoch;
    for (final k in _index.keys.toList()) {
      if (k is String && k.startsWith(_tombPrefix) && (_index.get(k) as int) < cutoff) await _index.delete(k);
    }
  }

  // ── Writing ──────────────────────────────────────────────────────────────

  Iterable<Map<dynamic, dynamic>> get _entries => [
        for (final k in _index.keys)
          if (k is String && !k.startsWith('_')) _index.get(k) as Map<dynamic, dynamic>,
      ];

  Map<String, dynamic> _entry(Map<String, dynamic> m, String key) => {
        'k': key,
        'u': m['mine'] != true && m['seen'] == null,
        if (m['exp'] != null) 'e': m['exp'],
      };

  /// Adds or replaces a message. Its place in the chat follows `at`; when `at` changes (the server's time
  /// replaces the phone's), the message moves.
  Future<void> put(Map<String, dynamic> m, {Uint8List? media}) => _locked(() => _put(m, media: media));

  Future<void> _put(Map<String, dynamic> m, {Uint8List? media}) async {
    final id = m['id'] as String;
    final old = _index.get(id) as Map<dynamic, dynamic>?;
    var at = m['at'] as int;
    final oldKey = old?['k'] as String?;
    var key = _keyFor(at);
    if (oldKey != null && oldKey.compareTo(key) != 0) {
      // Moved (the server's time replaces the phone's), or sharing its microsecond with another message.
      if (_sameSpot(oldKey, at)) {
        key = oldKey;
      } else {
        await _messages.delete(oldKey);
        _sorted = null;
      }
    }
    // Two messages in the same microsecond: the later one goes just after.
    while (key != oldKey && _messages.containsKey(key)) {
      key = _keyFor(++at);
    }
    if (oldKey == null || oldKey != key) _sorted = null;
    await _messages.put(key, m);
    await _index.put(id, _entry(m, key));
    if (media != null) await _media.put(id, media);
    _changes.add(null);
  }

  /// Changes one message with [change]; false when it is not here.
  /// [key] is [at] itself or one of the few places just after it (taken by another message).
  bool _sameSpot(String key, int at) {
    final n = int.tryParse(key);
    return n != null && n >= at && n - at < 16;
  }

  Future<bool> update(String id, Map<String, dynamic> Function(Map<String, dynamic> current) change) => _locked(() async {
        final current = await get(id);
        if (current == null) return false;
        await _put(change(current));
        return true;
      });

  Future<void> delete(Iterable<String> ids) => _locked(() async {
    var any = false;
    for (final id in ids) {
      final entry = _index.get(id) as Map<dynamic, dynamic>?;
      if (entry == null) continue;
      any = true;
      await _tombstone(id);
      await _messages.delete(entry['k']);
      await _media.delete(id);
      await _index.delete(id);
    }
    if (any) {
      _sorted = null;
      _changes.add(null);
    }
    await _dropOldTombstones();
  });

  Future<void> clear() => _locked(() async {
    await _messages.clear();
    await _media.clear();
    for (final k in _index.keys.toList()) {
      if (k is String && !k.startsWith('_')) await _index.delete(k);
    }
    for (final k in _index.keys.toList()) {
      if (k is String && k.startsWith(_tombPrefix)) await _index.delete(k);
    }
    _sorted = null;
    _changes.add(null);
  });

  // ── Reading ──────────────────────────────────────────────────────────────

  bool has(String id) => _index.containsKey(id);

  Future<Map<String, dynamic>?> get(String id) async {
    final entry = _index.get(id) as Map<dynamic, dynamic>?;
    if (entry == null) return null;
    final m = await _messages.get(entry['k']);
    return m == null ? null : Map<String, dynamic>.from(m as Map);
  }

  List<String> get _keys => _sorted ??= (_entries.map((e) => e['k'] as String).toList()..sort());

  /// Up to [limit] messages, newest last. With [before] (a message's `at`), only older ones.
  Future<List<Map<String, dynamic>>> page({int? before, required int limit}) async {
    final keys = _keys;
    var end = keys.length;
    if (before != null) {
      // First key that is >= before.
      final limitKey = _keyFor(before);
      var lo = 0, hi = keys.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (keys[mid].compareTo(limitKey) < 0) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      end = lo;
    }
    final start = end - limit < 0 ? 0 : end - limit;
    return [
      for (final k in keys.sublist(start, end))
        if (await _messages.get(k) case final Map m) Map<String, dynamic>.from(m),
    ];
  }

  /// How many messages exist (without reading them).
  int get count => _keys.length;

  /// Whether messages older than [at] exist.
  bool hasOlderThan(int at) => _keys.isNotEmpty && _keys.first.compareTo(_keyFor(at)) < 0;

  /// Partner messages not read yet.
  int get unreadCount => _entries.where((e) => e['u'] == true).length;

  /// Ids whose timer has run out.
  List<String> expiredIds(DateTime now) {
    final t = now.toUtc().microsecondsSinceEpoch;
    return [
      for (final k in _index.keys)
        if (k is String && !k.startsWith('_') && _expiry(k) <= t) k,
    ];
  }

  int _expiry(String id) => ((_index.get(id) as Map)['e'] as int?) ?? 1 << 62;

  /// Ids sent at or before [at].
  List<String> idsAtOrBefore(int at) => [
        for (final k in _index.keys)
          if (k is String && !k.startsWith('_') && ((_index.get(k) as Map)['k'] as String).compareTo(_keyFor(at + 1)) < 0) k,
      ];

  Future<Uint8List?> mediaBytes(String id) async {
    final b = await _media.get(id);
    return b == null ? null : Uint8List.fromList((b as List).cast<int>());
  }

  Future<void> dispose() => _changes.close();
}
