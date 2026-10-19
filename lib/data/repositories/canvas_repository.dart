import 'dart:typed_data';
import 'dart:ui';

import 'package:firebase_database/firebase_database.dart';
import 'package:rxdart/rxdart.dart';

import '../../domain/entities/canvas_stroke.dart';
import '../../domain/repositories/i_canvas_repository.dart';
import '../datasources/remote/rtdb_source.dart';
import '../models/canvas_stroke_model.dart';

class CanvasRepository implements ICanvasRepository {
  CanvasRepository({required this.rtdbSource});

  final RtdbSource rtdbSource;

  @override
  Future<void> pushStroke(CanvasStroke stroke) =>
      rtdbSource.strokeRef(stroke.coupleId, stroke.id).set({
        'coupleId':   stroke.coupleId,
        'userId':     stroke.userId,
        'color':      stroke.color.toARGB32().toString(),
        'width':      stroke.width,
        'isEraser':   stroke.isEraser,
        'isComplete': false,
        'timestamp':  stroke.timestamp.millisecondsSinceEpoch,
      });

  @override
  Future<void> pushStrokeChunk(
    String coupleId,
    String strokeId,
    int seq,
    List<Offset> points,
  ) {
    // Flat [x0, y0, x1, y1, …] — one small write per batch. The padded key
    // keeps chunks a Map in RTDB (sequential int keys would turn into a List).
    final flat = <double>[for (final p in points) ...[p.dx, p.dy]];
    return rtdbSource
        .strokeRef(coupleId, strokeId)
        .child('chunks/${CanvasStrokeModel.chunkKey(seq)}')
        .set(flat);
  }

  @override
  Future<void> completeStroke(String coupleId, String strokeId) =>
      rtdbSource.strokeRef(coupleId, strokeId).update({'isComplete': true});

  @override
  Stream<CanvasStroke> watchRemoteStrokes(String coupleId, String excludeUserId) {
    final ref = rtdbSource.canvasRef(coupleId).child('strokes');

    // A single malformed stroke must not kill the whole stream.
    CanvasStroke? parse(DatabaseEvent event) {
      try {
        final val = event.snapshot.value;
        if (val is! Map) return null;
        final stroke = CanvasStrokeModel.fromJson(
          event.snapshot.key!,
          Map<String, dynamic>.from(val),
        );
        return stroke.userId == excludeUserId ? null : stroke;
      } catch (_) {
        return null;
      }
    }

    // onChildAdded replays existing strokes; onChildChanged delivers live chunks.
    return ref.onChildAdded
        .map(parse)
        .mergeWith([ref.onChildChanged.map(parse)])
        .whereType<CanvasStroke>();
  }

  @override
  Future<int> clearCanvas(String coupleId) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    // Timestamp first, so the partner's baseline check sees a new value even
    // if the strokes removal arrives separately.
    await rtdbSource.canvasClearedRef(coupleId).set(ts);
    await rtdbSource.canvasRef(coupleId).child('strokes').remove();
    return ts;
  }

  @override
  Stream<int> watchCanvasCleared(String coupleId) {
    return rtdbSource
        .canvasClearedRef(coupleId)
        .onValue
        .map((event) => (event.snapshot.value as num?)?.toInt() ?? 0)
        .distinct();
  }

  @override
  Future<String> saveCanvasBitmap(String coupleId, Uint8List bytes) async {
    // Storage requires Blaze plan — returns empty string; UI falls back to emoji thumbnail.
    return '';
  }
}
