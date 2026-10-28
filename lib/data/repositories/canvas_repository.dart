import 'dart:async';
import 'dart:ui';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/outbox_service.dart';
import '../../domain/entities/canvas_stroke.dart';
import '../../domain/repositories/i_canvas_repository.dart';
import '../datasources/remote/couple_channel_source.dart';
import '../datasources/remote/storage_source.dart';

/// Live strokes travel as Broadcast events on the couple channel; a finished
/// stroke is persisted to `canvas_strokes` so a partner who joins later (or
/// reopens the canvas) can load it.
class CanvasRepository implements ICanvasRepository {
  CanvasRepository({
    required this.client,
    required this.channelSource,
    required this.storage,
    required this.outbox,
  }) {
    outbox.register(_strokeType, _deliverStroke);
    outbox.register(_strokesType, _deliverStrokes);
    outbox.register(_clearType, _deliverClear);
  }

  /// One stroke per change. No longer created, but changes queued by an earlier
  /// version of the app may still carry it.
  static const _strokeType  = 'stroke';
  static const _strokesType = 'strokes';

  /// Finished strokes wait this long for company before being saved together,
  /// or are saved at once when this many are waiting.
  static const _batchDelay = Duration(seconds: 3);
  static const _batchSize  = 20;
  static const _clearType  = 'canvasClear';

  /// A stroke that reaches the server later than this was drawn offline, so the
  /// partner never saw it live and it is replayed to them.
  static const _lateAfter = Duration(seconds: 10);

  final SupabaseClient      client;
  final StorageSource       storage;
  final CoupleChannelSource channelSource;
  final OutboxService       outbox;

  final _finished = <Map<String, dynamic>>[];
  Timer? _batchTimer;

  /// Live events go out one after another. Each is its own network call, and
  /// without this a stroke's end (or last chunk) can overtake its start and be
  /// dropped by the partner.
  Future<void> _sendQueue = Future.value();
  Future<void> _sendInOrder(String coupleId, String event, Map<String, dynamic> payload) {
    final next = _sendQueue.then((_) => channelSource.open(coupleId).send(event, payload));
    _sendQueue = next.catchError((_) {});
    return next;
  }

  /// Own strokes in flight, kept so the whole stroke can be persisted on completion.
  final _own = <String, _PendingStroke>{};

  @override
  Future<void> pushStroke(CanvasStroke stroke) {
    _own[stroke.id] = _PendingStroke(stroke);
    return _sendInOrder(stroke.coupleId, CoupleChannel.strokeStart, {
      'id':        stroke.id,
      'user_id':   stroke.userId,
      'color':     stroke.color.toARGB32(),
      'width':     stroke.width,
      'is_eraser': stroke.isEraser,
      'timestamp': stroke.timestamp.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> pushStrokeChunk(String coupleId, String strokeId, int seq, List<Offset> points) {
    // Flat [x0, y0, x1, y1, …] — one small message per batch.
    final flat = <double>[for (final p in points) ...[p.dx, p.dy]];
    _own[strokeId]?.chunks[seq] = flat;
    return _sendInOrder(coupleId, CoupleChannel.strokeChunk, {
      'id':  strokeId,
      'seq': seq,
      'pts': flat,
    });
  }

  @override
  Future<void> completeStroke(String coupleId, String strokeId) async {
    final pending = _own.remove(strokeId);
    // Tells a partner who is watching live; nothing waits on it.
    // The chunk count lets the partner tell whether anything is still missing.
    _sendInOrder(coupleId, CoupleChannel.strokeEnd, {
      'id':     strokeId,
      'chunks': pending?.chunks.length,
    }).ignore();
    if (pending == null) return;

    // Strokes are saved in batches: drawing makes many, and a request each is
    // far more traffic than the partner (who already saw them live) needs.
    final s = pending.stroke;
    _finished.add({
      'id':        s.id,
      'coupleId':  coupleId,
      'userId':    s.userId,
      'color':     s.color.toARGB32(),
      'width':     s.width,
      'isEraser':  s.isEraser,
      'points':    pending.flatPoints(),
      'timestamp': s.timestamp.millisecondsSinceEpoch,
    });
    if (_finished.length >= _batchSize) {
      await flushStrokes();
    } else {
      _batchTimer ??= Timer(_batchDelay, () => flushStrokes().ignore());
    }
  }

  @override
  Future<void> flushStrokes() async {
    _batchTimer?.cancel();
    _batchTimer = null;
    if (_finished.isEmpty) return;
    final items = List<Map<String, dynamic>>.of(_finished);
    _finished.clear();
    // Through the outbox, so strokes drawn without a connection are kept and sent later.
    await outbox.submit(_strokesType, {'items': items});
  }

  Future<void> _deliverStrokes(Map<String, dynamic> p) async {
    final items = [for (final i in (p['items'] as List)) Map<String, dynamic>.from(i as Map)];
    if (items.isEmpty) return;
    // Insert the batch in one request; a stroke an earlier attempt already saved is skipped.
    await client.from('canvas_strokes').upsert(
      [
        for (final i in items)
          {
            'id':         i['id'],
            'couple_id':  i['coupleId'],
            'user_id':    i['userId'],
            'color':      i['color'],
            'width':      i['width'],
            'is_eraser':  i['isEraser'],
            'points':     i['points'],
            'created_at': DateTime.fromMillisecondsSinceEpoch((i['timestamp'] as num).toInt(), isUtc: true)
                .toIso8601String(),
          },
      ],
      onConflict: 'id',
      ignoreDuplicates: true,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final i in items) {
      if (now - (i['timestamp'] as num).toInt() > _lateAfter.inMilliseconds) {
        await _replayLive(i['coupleId'] as String, i);
      }
    }
  }

  Future<void> _deliverStroke(Map<String, dynamic> p) async {
    final coupleId  = p['coupleId'] as String;
    final timestamp = (p['timestamp'] as num).toInt();
    try {
      await client.from('canvas_strokes').insert({
        'id':         p['id'],
        'couple_id':  coupleId,
        'user_id':    p['userId'],
        'color':      p['color'],
        'width':      p['width'],
        'is_eraser':  p['isEraser'],
        'points':     p['points'],
        'created_at': DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true).toIso8601String(),
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // an earlier attempt already got through
      rethrow;
    }

    final age = DateTime.now().millisecondsSinceEpoch - timestamp;
    if (age > _lateAfter.inMilliseconds) {
      await _replayLive(coupleId, p);
    }
  }

  /// Shows the partner a stroke they missed. The database already has it, so
  /// this is best effort: if they are not watching, they load it next time.
  Future<void> _replayLive(String coupleId, Map<String, dynamic> p) async {
    try {
      final channel = channelSource.open(coupleId);
      await Future<void>(() async {
        await channel.send(CoupleChannel.strokeStart, {
          'id':        p['id'],
          'user_id':   p['userId'],
          'color':     p['color'],
          'width':     p['width'],
          'is_eraser': p['isEraser'],
          'timestamp': p['timestamp'],
        });
        await channel.send(CoupleChannel.strokeChunk, {'id': p['id'], 'seq': 0, 'pts': p['points']});
        await channel.send(CoupleChannel.strokeEnd, {'id': p['id']});
      }).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  @override
  Stream<CanvasStroke> watchRemoteStrokes(String coupleId, String excludeUserId) {
    final channel = channelSource.open(coupleId);
    final out     = StreamController<CanvasStroke>();
    final subs    = <StreamSubscription<dynamic>>[];

    // Partner strokes being drawn right now, keyed by stroke id.
    final live = <String, _PendingStroke>{};
    // Chunks that arrived before their stroke's start.
    final early = <String, Map<int, List<dynamic>>>{};
    // Strokes whose end arrived while chunks were still missing: id -> chunk count.
    final expected = <String, int>{};
    final waiting  = <String, Timer>{};
    // Points last shown per stroke, and finished strokes to double-check against
    // the saved copy (a broadcast that was dropped leaves a stroke incomplete).
    final shown     = <String, int>{};
    final attempts  = <String, int>{};
    Timer? reconcileTimer;

    void emit(CanvasStroke stroke) {
      shown[stroke.id] = stroke.points.length;
      if (!out.isClosed) out.add(stroke);
    }

    Future<void> reconcile() async {
      final ids = attempts.keys.toList();
      if (ids.isEmpty || out.isClosed) return;
      try {
        final rows = await client.from('canvas_strokes').select().inFilter('id', ids);
        for (final row in rows) {
          final id = row['id'] as String;
          attempts.remove(id);
          final saved = (row['points'] as List).length ~/ 2;
          if (saved > (shown[id] ?? -1)) emit(strokeFromRow(row));
        }
      } catch (_) {}
      // Not saved yet (the sender batches, or is offline): look again a few times.
      for (final id in ids) {
        final n = attempts[id];
        if (n == null) continue;
        if (n >= 3) {
          attempts.remove(id);
        } else {
          attempts[id] = n + 1;
        }
      }
      if (attempts.isNotEmpty) reconcileTimer = Timer(const Duration(seconds: 5), reconcile);
    }

    void finish(String id) {
      waiting.remove(id)?.cancel();
      expected.remove(id);
      final pending = live.remove(id);
      if (pending == null) return;
      emit(pending.snapshot(isComplete: true));
      attempts[id] = 0;
      reconcileTimer?.cancel();
      reconcileTimer = Timer(const Duration(seconds: 5), reconcile);
    }

    out.onListen = () async {
      // Live events first, so nothing is missed while the history loads.
      subs.add(channel.on(CoupleChannel.strokeStart).listen((m) {
        final userId = m['user_id'] as String?;
        final id     = m['id']      as String?;
        if (userId == null || id == null || userId == excludeUserId) return;
        final stroke = CanvasStroke(
          id:        id,
          coupleId:  coupleId,
          userId:    userId,
          color:     Color((m['color'] as num).toInt()),
          width:     (m['width'] as num).toDouble(),
          isEraser:  m['is_eraser'] as bool? ?? false,
          timestamp: DateTime.fromMillisecondsSinceEpoch((m['timestamp'] as num).toInt()),
        );
        final pending = live[id] = _PendingStroke(stroke);
        early.remove(id)?.forEach((seq, pts) => pending.chunks[seq] = pts);
        emit(pending.snapshot());
      }));

      subs.add(channel.on(CoupleChannel.strokeChunk).listen((m) {
        final id  = m['id'];
        final pts = m['pts'];
        if (id is! String || pts is! List) return;
        final seq     = (m['seq'] as num).toInt();
        final pending = live[id];
        if (pending == null) {
          // Overtook its start: keep it until the start shows up.
          early.putIfAbsent(id, () => {})[seq] = pts;
          return;
        }
        pending.chunks[seq] = pts;
        emit(pending.snapshot());
        final want = expected[id];
        if (want != null && pending.chunks.length >= want) finish(id);
      }));

      subs.add(channel.on(CoupleChannel.strokeEnd).listen((m) {
        final id = m['id'];
        if (id is! String) return;
        final pending = live[id];
        if (pending == null) return;
        final want = (m['chunks'] as num?)?.toInt();
        if (want == null || pending.chunks.length >= want) {
          finish(id);
        } else {
          // The end overtook some chunks: give them a moment, then settle for
          // what arrived (the saved copy fills in the rest).
          expected[id] = want;
          waiting[id]  = Timer(const Duration(seconds: 3), () => finish(id));
        }
      }));

      subs.add(channel.on(CoupleChannel.canvasClear).listen((_) {
        live.clear();
        early.clear();
        expected.clear();
        attempts.clear();
        for (final t in waiting.values) {
          t.cancel();
        }
        waiting.clear();
      }));

      try {
        // Wait for the live channel so nothing is missed while the history loads,
        // but not forever: offline, the history can still be tried.
        await channel.whenReady();
        // Own strokes still waiting for their batch must be saved before they are read back.
        await flushStrokes().timeout(const Duration(seconds: 5)).catchError((_) {});
        // Everyone's strokes, including our own: reopening the canvas must show our drawing too.
        final rows = await client
            .from('canvas_strokes')
            .select()
            .eq('couple_id', coupleId)
            .order('created_at');
        for (final row in rows) {
          if (live.containsKey(row['id'])) continue; // already arriving live
          emit(strokeFromRow(row));
        }
      } catch (err, st) {
        if (!out.isClosed) out.addError(err, st);
      }
    };
    out.onCancel = () {
      reconcileTimer?.cancel();
      for (final t in waiting.values) {
        t.cancel();
      }
      for (final s in subs) {
        s.cancel();
      }
    };
    return out.stream;
  }

  @override
  Future<int> clearCanvas(String coupleId) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    // Queued behind any strokes drawn offline, so they are cleared in order.
    await outbox.submit(_clearType, {'coupleId': coupleId, 'timestamp': ts});
    return ts;
  }

  Future<void> _deliverClear(Map<String, dynamic> p) async {
    final coupleId = p['coupleId'] as String;
    await client.from('canvas_strokes').delete().eq('couple_id', coupleId);
    try {
      await channelSource
          .open(coupleId)
          .send(CoupleChannel.canvasClear, {'timestamp': p['timestamp']})
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Rows are gone; a partner who is watching sees it the next time they open the canvas.
    }
  }

  @override
  Stream<int> watchCanvasCleared(String coupleId) async* {
    // The first value is only a baseline (see CanvasBloc); then every clear.
    yield 0;
    yield* channelSource
        .open(coupleId)
        .on(CoupleChannel.canvasClear)
        .map((m) => (m['timestamp'] as num).toInt());
  }

  @override
  Future<void> enterCanvas(String coupleId, String userId) =>
      channelSource.open(coupleId).track({
        'user_id':    userId,
        'screen':     'canvas',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

  @override
  Future<void> leaveCanvas(String coupleId, String userId) =>
      channelSource.open(coupleId).track({
        'user_id':    userId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

  @override
  Stream<bool> watchPartnerOnCanvas(String coupleId, String partnerUserId) async* {
    final channel = channelSource.open(coupleId);
    await channel.ready;
    bool here() => channel.presenceScreens[partnerUserId] == 'canvas';
    yield here();
    yield* channel.onlineUsers.stream.map((_) => here()).distinct();
  }

  static CanvasStroke strokeFromRow(Map<String, dynamic> row) {
    final flat   = row['points'] as List;
    final points = <Offset>[
      for (var i = 0; i + 1 < flat.length; i += 2)
        Offset((flat[i] as num).toDouble(), (flat[i + 1] as num).toDouble()),
    ];
    return CanvasStroke(
      id:         row['id']        as String,
      coupleId:   row['couple_id'] as String,
      userId:     row['user_id']   as String,
      color:      Color((row['color'] as num).toInt()),
      width:      (row['width'] as num).toDouble(),
      timestamp:  DateTime.parse(row['created_at'] as String),
      points:     points,
      isEraser:   row['is_eraser'] as bool? ?? false,
      isComplete: true,
    );
  }
}

class _PendingStroke {
  _PendingStroke(this.stroke);
  final CanvasStroke stroke;
  final Map<int, List<dynamic>> chunks = {};

  List<double> flatPoints() {
    final keys = chunks.keys.toList()..sort();
    return [for (final k in keys) ...chunks[k]!.map((v) => (v as num).toDouble())];
  }

  CanvasStroke snapshot({bool isComplete = false}) {
    final flat   = flatPoints();
    final points = <Offset>[
      for (var i = 0; i + 1 < flat.length; i += 2) Offset(flat[i], flat[i + 1]),
    ];
    return CanvasStroke(
      id:         stroke.id,
      coupleId:   stroke.coupleId,
      userId:     stroke.userId,
      color:      stroke.color,
      width:      stroke.width,
      timestamp:  stroke.timestamp,
      points:     points,
      isEraser:   stroke.isEraser,
      isComplete: isComplete,
    );
  }
}
