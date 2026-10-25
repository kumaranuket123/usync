import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/canvas_stroke.dart';
import '../../domain/repositories/i_canvas_repository.dart';
import '../datasources/remote/couple_channel_source.dart';
import '../datasources/remote/storage_source.dart';

/// Live strokes travel as Broadcast events on the couple channel; a finished
/// stroke is persisted to `canvas_strokes` so a partner who joins later (or
/// reopens the canvas) can load it.
class CanvasRepository implements ICanvasRepository {
  CanvasRepository({required this.client, required this.channelSource, required this.storage});

  final SupabaseClient      client;
  final StorageSource       storage;
  final CoupleChannelSource channelSource;

  /// Own strokes in flight, kept so the whole stroke can be persisted on completion.
  final _own = <String, _PendingStroke>{};

  @override
  Future<void> pushStroke(CanvasStroke stroke) {
    _own[stroke.id] = _PendingStroke(stroke);
    return channelSource.open(stroke.coupleId).send(CoupleChannel.strokeStart, {
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
    return channelSource.open(coupleId).send(CoupleChannel.strokeChunk, {
      'id':  strokeId,
      'seq': seq,
      'pts': flat,
    });
  }

  @override
  Future<void> completeStroke(String coupleId, String strokeId) async {
    final channel = channelSource.open(coupleId);
    await channel.send(CoupleChannel.strokeEnd, {'id': strokeId});

    final pending = _own.remove(strokeId);
    if (pending == null) return;
    final s = pending.stroke;
    await client.from('canvas_strokes').insert({
      'id':         s.id,
      'couple_id':  coupleId,
      'user_id':    s.userId,
      'color':      s.color.toARGB32(),
      'width':      s.width,
      'is_eraser':  s.isEraser,
      'points':     pending.flatPoints(),
      'created_at': s.timestamp.toUtc().toIso8601String(),
    });
  }

  @override
  Stream<CanvasStroke> watchRemoteStrokes(String coupleId, String excludeUserId) {
    final channel = channelSource.open(coupleId);
    final out     = StreamController<CanvasStroke>();
    final subs    = <StreamSubscription<dynamic>>[];

    // Partner strokes being drawn right now, keyed by stroke id.
    final live = <String, _PendingStroke>{};

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
        live[id] = _PendingStroke(stroke);
        out.add(stroke);
      }));

      subs.add(channel.on(CoupleChannel.strokeChunk).listen((m) {
        final pending = live[m['id']];
        final pts     = m['pts'];
        if (pending == null || pts is! List) return;
        pending.chunks[(m['seq'] as num).toInt()] = pts;
        out.add(pending.snapshot());
      }));

      subs.add(channel.on(CoupleChannel.strokeEnd).listen((m) {
        final pending = live.remove(m['id']);
        if (pending != null) out.add(pending.snapshot(isComplete: true));
      }));

      subs.add(channel.on(CoupleChannel.canvasClear).listen((_) => live.clear()));

      try {
        await channel.ready;
        final rows = await client
            .from('canvas_strokes')
            .select()
            .eq('couple_id', coupleId)
            .neq('user_id', excludeUserId)
            .order('created_at');
        for (final row in rows) {
          if (live.containsKey(row['id'])) continue; // already arriving live
          final stroke = _fromRow(row);
          if (!out.isClosed) out.add(stroke);
        }
      } catch (err, st) {
        if (!out.isClosed) out.addError(err, st);
      }
    };
    out.onCancel = () {
      for (final s in subs) {
        s.cancel();
      }
    };
    return out.stream;
  }

  @override
  Future<int> clearCanvas(String coupleId) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    await client.from('canvas_strokes').delete().eq('couple_id', coupleId);
    await channelSource.open(coupleId).send(CoupleChannel.canvasClear, {'timestamp': ts});
    return ts;
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

  @override
  Future<String> saveCanvasBitmap(String coupleId, Uint8List bytes) =>
      storage.uploadPng(coupleId, bytes);

  static CanvasStroke _fromRow(Map<String, dynamic> row) {
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
