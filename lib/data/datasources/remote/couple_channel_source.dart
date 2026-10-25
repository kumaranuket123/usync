import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// One private Realtime channel per couple (`couple:<id>`), shared by presence,
/// touch and live canvas strokes. Access is enforced by the `realtime.messages`
/// RLS policies. All listeners are registered before `subscribe()`.
class CoupleChannel {
  CoupleChannel._(this.coupleId, this._client) {
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

    final done = Completer<void>();
    ch.subscribe((status, error) {
      if (done.isCompleted) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        done.complete();
      } else if (error != null || status == RealtimeSubscribeStatus.channelError) {
        done.completeError(error ?? 'Realtime channel error');
      }
    });
    ready = done.future;
  }

  final String         coupleId;
  final SupabaseClient _client;
  late final RealtimeChannel _channel;
  late final Future<void>    ready;

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

  Future<void> send(String event, Map<String, dynamic> payload) async {
    await ready;
    await _channel.sendBroadcastMessage(event: event, payload: payload);
  }

  Future<void> track(Map<String, dynamic> state) async {
    await ready;
    await _channel.track(state);
  }

  Future<void> untrack() async {
    await ready;
    await _channel.untrack();
  }

  void dispose() {
    _channel.unsubscribe();
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
}
