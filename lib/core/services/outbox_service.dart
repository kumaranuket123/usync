import '../crypto/content_cipher.dart';
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/network_errors.dart';

/// Sends one queued change to the server. Must be safe to run twice (the first
/// attempt may have reached the server even though the answer was lost), so
/// handlers use ids chosen when the change was made.
typedef OutboxHandler = Future<void> Function(Map<String, dynamic> payload);

/// Changes made without a connection wait here, on the device, until they can
/// be sent, then go out in the order they were made so the partner sees them.
///
/// [submit] is the only entry point: online it sends straight away, otherwise
/// (or when the send fails for lack of a connection) it queues the change.
class OutboxService extends ChangeNotifier {
  OutboxService({
    required Box<dynamic> box,
    Connectivity? connectivity,
    this.retryEvery  = const Duration(seconds: 30),
    this.maxAttempts = 5,
    this.sendTimeout = const Duration(seconds: 20),
  })  : _box = box,
        _connectivity = connectivity ?? Connectivity();

  final Box<dynamic>  _box;
  final Connectivity  _connectivity;
  final Duration      retryEvery;
  /// Failures that are not about the connection (a rejected row) are retried
  /// this many times, then dropped so they cannot block everything behind them.
  final int           maxAttempts;
  /// A send that takes longer counts as a lost connection (Wi-Fi with no
  /// internet can hang for a minute). Safe because every change can be repeated.
  final Duration      sendTimeout;

  final _handlers = <String, OutboxHandler>{};
  bool _online   = true;
  bool _flushing = false;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get online  => _online;
  bool get syncing => _flushing;
  /// Changes waiting to be sent.
  int  get pending => _box.length;

  void register(String type, OutboxHandler handler) => _handlers[type] = handler;

  Future<void> init() async {
    _online = _hasConnection(await _connectivity.checkConnectivity());
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _online;
      _online = _hasConnection(results);
      notifyListeners();
      if (_online && !wasOnline) unawaited(flush());
    });
    // The connection check only says a network is attached, not that the
    // server is reachable, so keep trying while anything is waiting.
    _timer = Timer.periodic(retryEvery, (_) {
      if (pending > 0) unawaited(flush());
    });
    notifyListeners();
    unawaited(flush());
  }

  static bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  /// Sends the change now if possible; otherwise queues it. Returns true when
  /// it reached the server, false when it is waiting in the queue. Errors that
  /// are not about the connection are thrown to the caller.
  Future<bool> submit(String type, Map<String, dynamic> payload) async {
    final handler = _handlers[type];
    if (handler == null) throw StateError('No outbox handler registered for "$type"');

    // Behind anything already waiting, so changes keep their order.
    if (pending == 0 && _online) {
      try {
        await handler(payload).timeout(sendTimeout);
        return true;
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
      }
    }
    await _box.add({
      'type':      type,
      'payload':   payload,
      'createdAt': DateTime.now().toIso8601String(),
      'attempts':  0,
    });
    notifyListeners();
    if (_online) unawaited(flush());
    return false;
  }

  Future<void>? _inflight;

  /// Sends everything waiting, oldest first. Stops at the first connection
  /// failure and tries again later. A call while one is already running waits
  /// for that run, so awaiting it always means "everything that could be sent
  /// has been".
  Future<void> flush() => _inflight ??= _run().whenComplete(() => _inflight = null);

  Future<void> _run() async {
    if (pending == 0) return;
    _flushing = true;
    notifyListeners();
    try {
      // Changes made while this runs are picked up by another pass; each change
      // is tried at most once per run, so a rejected one does not burn through
      // its attempts while others are still going out.
      final tried = <dynamic>{};
      var sentSomething = true;
      while (sentSomething && pending > 0) {
        sentSomething = false;
        for (final key in _box.keys.toList()) {
          if (!tried.add(key)) continue;
          final entry = _box.get(key);
          if (entry is! Map) {
            await _box.delete(key);
            continue;
          }
          final handler = _handlers[entry['type']];
          if (handler == null) continue; // from a newer version of the app: keep it
          try {
            await handler(_deepCopy(entry['payload'])).timeout(sendTimeout);
            await _box.delete(key);
            sentSomething = true;
          } catch (e) {
            // No connection, or no couple key yet: keep it and try again later, without counting an attempt.
            if (isNetworkError(e) || e is EncryptionNotReady) return;
            final attempts = ((entry['attempts'] as int?) ?? 0) + 1;
            if (attempts >= maxAttempts) {
              debugPrint('Outbox: dropping ${entry['type']} after $attempts failed attempts: $e');
              await _box.delete(key);
            } else {
              await _box.put(key, {...entry.cast<String, dynamic>(), 'attempts': attempts});
            }
          }
          notifyListeners();
        }
      }
    } finally {
      _flushing = false;
      notifyListeners();
    }
  }

  /// Hive hands back loosely typed maps; handlers expect `Map<String, dynamic>`.
  static Map<String, dynamic> _deepCopy(Object? value) =>
      Map<String, dynamic>.from(value as Map);

  /// Discards everything waiting (used at sign-out, so one account's changes
  /// are never sent as another's).
  Future<void> clear() async {
    await _box.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
