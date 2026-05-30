import 'dart:typed_data';

import 'package:rxdart/rxdart.dart';

import 'package:firebase_database/firebase_database.dart';

import '../../domain/entities/canvas_stroke.dart';
import '../../domain/repositories/i_canvas_repository.dart';
import '../datasources/remote/rtdb_source.dart';
import '../models/canvas_stroke_model.dart';

class CanvasRepository implements ICanvasRepository {
  CanvasRepository({required this.rtdbSource, Object? storage});

  final RtdbSource rtdbSource;

  @override
  Future<void> pushStroke(CanvasStroke stroke) async {
    await rtdbSource.strokeRef(stroke.coupleId, stroke.id).set({
      'coupleId':   stroke.coupleId,
      'userId':     stroke.userId,
      'color':      stroke.color.value.toString(),
      'width':      stroke.width,
      'isEraser':   stroke.isEraser,
      'isComplete': false,
      'timestamp':  stroke.timestamp.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> pushStrokePoint(String coupleId, String strokeId, double x, double y) =>
      rtdbSource.strokePointsRef(coupleId, strokeId).push().set({'x': x, 'y': y});

  @override
  Future<void> pushCompleteStroke(CanvasStroke stroke) async {
    // Write the full stroke with ordered points in a single RTDB call.
    await rtdbSource.strokeRef(stroke.coupleId, stroke.id).set({
      'coupleId':   stroke.coupleId,
      'userId':     stroke.userId,
      'color':      stroke.color.value.toString(),
      'width':      stroke.width,
      'isEraser':   stroke.isEraser,
      'isComplete': true,
      'timestamp':  stroke.timestamp.millisecondsSinceEpoch,
      // Plain list — no push-key scrambling, always correct order.
      'points': stroke.points
          .map((o) => {'x': o.dx, 'y': o.dy})
          .toList(),
    });
  }

  @override
  Future<void> completeStroke(String coupleId, String strokeId) =>
      rtdbSource.strokeRef(coupleId, strokeId).update({'isComplete': true});

  @override
  Stream<CanvasStroke> watchRemoteStrokes(String coupleId, String excludeUserId) {
    final ref = rtdbSource.canvasRef(coupleId).child('strokes');

    CanvasStroke? _parse(DatabaseEvent event) {
      final val = event.snapshot.value;
      if (val == null) return null;
      final data   = Map<String, dynamic>.from(val as Map);
      final stroke = CanvasStrokeModel.fromJson(event.snapshot.key!, data);
      return stroke.userId == excludeUserId ? null : stroke;
    }

    // Merge onChildAdded (new strokes) + onChildChanged (point updates)
    final added   = ref.onChildAdded.map(_parse).where((s) => s != null).cast<CanvasStroke>();
    final changed = ref.onChildChanged.map(_parse).where((s) => s != null).cast<CanvasStroke>();

    return added.mergeWith([changed]);
  }

  @override
  Future<void> clearCanvas(String coupleId) async {
    // Remove all strokes then write a clear timestamp so both phones detect the event.
    await rtdbSource.canvasRef(coupleId).child('strokes').remove();
    await rtdbSource.canvasClearedRef(coupleId)
        .set(DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Stream<void> watchCanvasCleared(String coupleId) {
    return rtdbSource
        .canvasClearedRef(coupleId)
        .onValue
        .where((event) => event.snapshot.value != null)
        .map((_) => null);
  }

  @override
  Future<String> saveCanvasBitmap(String coupleId, Uint8List bytes) async {
    // Storage requires Blaze plan — returns empty string; UI falls back to emoji thumbnail.
    return '';
  }
}
