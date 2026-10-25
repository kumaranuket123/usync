import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One private Realtime channel per couple (`couple:<id>`), shared by presence,
/// touch and live canvas strokes. Access is enforced by the `realtime.messages`
/// RLS policies.
///
/// The channel looks after itself:
/// - the Realtime library rejoins a channel after a dropped connection, but it
///   never rejoins one the *server closed* (for example when the session
///   changes), so that case is detected here and a fresh channel is made;
/// - Presence belongs to the connection and is lost on every (re)join, so the
///   last announced state is sent again whenever the channel is joined;
/// - callers are never left waiting forever for a connection: they wait a few
///   seconds at most, then carry on (a broadcast falls back to HTTP delivery).
///
/// Listeners live on streams owned by this object, so they keep working across
/// reconnects.
class CoupleChannel {
  CoupleChannel._(this.coupleId, this._client) {
    _connect();
  }

  final String         coupleId;
  final SupabaseClient _client;

  RealtimeChannel? _channel;
  bool   _disposed = false;
  /// The current channel is joined right now (kept from the join status, since
  /// the library's own flags are internal).
  bool   _joined   = false;
  int    _failures = 0;
  Timer? _reconnectTimer;
  /// What this user last announced on Presence, sent again after every (re)join.
  Map<String, dynamic>? _tracked;
  final _ready = Completer<void>();

  /// Completes the first time the channel is joined. It never completes with an
  /// error, so a failed first attempt cannot poison later sends.
  Future<void> get ready => _ready.future;

  /// Waits for the channel to be joined, but only for [timeout].
  Future<void> whenReady([Duration timeout = const Duration(seconds: 5)]) =>
      ready.timeout(timeout, onTimeout: () {});

  void _log(String message) {
    if (kDebugMode) debugPrint('[realtime couple:$coupleId] $message');
  }

  void _connect() {
    if (_disposed) return;
    final ch = _channel = _client.channel(
      'couple:$coupleId',
      opts: const RealtimeChannelConfig(private: true),
    );

    ch.onPresenceSync((_) {
      final online = <String>{
        for (final state in ch.presenceState())
          for (final p in state.presences)
            if (p.payload['user_id'] is String) p.payload['user_id'] as String,
      };
      // Which screen each user announced (e.g. 'touch'); null when none.
      presenceScreens = {
        for (final state in ch.presenceState())
          for (final p in state.presences)
            if (p.payload['user_id'] is String)
              p.payload['user_id'] as String: p.payload['screen'] as String?,
      };
      presenceSynced = true;
      if (!onlineUsers.isClosed) onlineUsers.add(online);
    });

    for (final entry in _events.entries) {
      ch.onBroadcast(event: entry.key, callback: (msg) {
        if (!entry.value.isClosed) entry.value.add(_unwrap(msg));
      });
    }

    ch.subscribe((status, error) {
      // A late callback from a channel we already replaced or disposed.
      if (_disposed || !identical(ch, _channel)) return;
      _log('status ${status.name}${error == null ? '' : ' ($error)'}');
      _joined = status == RealtimeSubscribeStatus.subscribed;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _failures = 0;
          if (!_ready.isCompleted) _ready.complete();
          final tracked = _tracked;
          if (tracked != null) ch.track(tracked).ignore();
        case RealtimeSubscribeStatus.closed:
          _scheduleReconnect();
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          // The library retries these on its own.
          break;
      }
    });
  }

  /// The server closed the channel and the library will not rejoin it: replace
  /// it, waiting a little longer after each failure so a refusal is not hammered.
  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer != null) return;
    final seconds = (1 << _failures.clamp(0, 5)).clamp(1, 30);
    _failures++;
    _log('closed by the server, reconnecting in ${seconds}s');
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      // Forget the old channel first: removing it reports "closed" once more,
      // and that must not schedule another reconnect.
      final old = _channel;
      _channel = null;
      _joined  = false;
      if (old != null) _client.removeChannel(old).ignore();
      _connect();
    });
  }

  /// Latest screen announced by each online user (from Presence).
  Map<String, String?> presenceScreens = const {};
  /// False until the first Presence sync, when [presenceScreens] is still empty.
  bool presenceSynced = false;

  /// Latest set of online user ids (from Presence).
  final onlineUsers = StreamController<Set<String>>.broadcast();

  static const touch       = 'touch';
  static const strokeStart = 'stroke_start';
  static const strokeChunk = 'stroke_chunk';
  static const strokeEnd   = 'stroke_end';
  static const canvasClear = 'canvas_clear';

  final Map<String, StreamController<Map<String, dynamic>>> _events = {
    for (final e in [touch, strokeStart, strokeChunk, strokeEnd, canvasClear])
      e: StreamController<Map<String, dynamic>>.broadcast(),
  };

  Stream<Map<String, dynamic>> on(String event) => _events[event]!.stream;

  /// Different client versions deliver either the sent payload or the full
  /// `{type, event, payload}` envelope; accept both.
  static Map<String, dynamic> _unwrap(Map<String, dynamic> msg) {
    final inner = msg['payload'];
    if (inner is Map && msg.containsKey('event')) return Map<String, dynamic>.from(inner);
    return msg;
  }

  /// Sends a broadcast. If the channel is not joined (yet, or just now) the
  /// library delivers it over HTTP instead, so a short gap does not lose it.
  Future<void> send(String event, Map<String, dynamic> payload) async {
    await whenReady(const Duration(seconds: 3));
    final ch = _channel;
    if (ch == null || _disposed) return;
    final result = await ch.sendBroadcastMessage(event: event, payload: payload);
    if (result != ChannelResponse.ok) _log('send "$event" -> ${result.name}');
  }

  Future<void> track(Map<String, dynamic> state) async {
    _tracked = state; // sent again whenever the channel is (re)joined
    await whenReady(const Duration(seconds: 3));
    final ch = _channel;
    // Not joined: nothing to send it on now, and the join will send it. (Asking
    // the library to track on an unjoined channel waits out its own long timeout.)
    if (ch == null || _disposed || !_joined) return;
    await ch.track(state);
  }

  Future<void> untrack() async {
    _tracked = null;
    await whenReady(const Duration(seconds: 3));
    final ch = _channel;
    if (ch == null || _disposed || !_joined) return;
    await ch.untrack();
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    final ch = _channel;
    if (ch != null) _client.removeChannel(ch).ignore();
    onlineUsers.close();
    for (final c in _events.values) {
      c.close();
    }
  }
}

class CoupleChannelSource {
  CoupleChannelSource({required this.client});
  final SupabaseClient client;

  CoupleChannel? _current;

  CoupleChannel open(String coupleId) {
    final current = _current;
    if (current != null && current.coupleId == coupleId) return current;
    current?.dispose();
    return _current = CoupleChannel._(coupleId, client);
  }

  /// Drops the channel (at sign-out), so the next account or session starts a
  /// fresh one instead of inheriting this session's.
  void close() {
    _current?.dispose();
    _current = null;
  }
}
