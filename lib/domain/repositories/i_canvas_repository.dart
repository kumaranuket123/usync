import 'dart:typed_data';
import 'dart:ui';

import '../entities/canvas_stroke.dart';

abstract interface class ICanvasRepository {
  /// Creates the stroke node (metadata only, `isComplete: false`).
  Future<void>          pushStroke(CanvasStroke stroke);

  /// Appends a batch of points so the partner sees the stroke while it is drawn.
  /// [seq] orders chunks within the stroke.
  Future<void>          pushStrokeChunk(String coupleId, String strokeId, int seq, List<Offset> points);
  Future<void>          completeStroke(String coupleId, String strokeId);
  Stream<CanvasStroke>  watchRemoteStrokes(String coupleId, String excludeUserId);

  /// Removes all strokes and returns the clear timestamp written for the partner.
  Future<int>           clearCanvas(String coupleId);

  /// Emits the current `clearedAt` timestamp (0 if never cleared), then every change.
  Stream<int>           watchCanvasCleared(String coupleId);
  Future<String>        saveCanvasBitmap(String coupleId, Uint8List bytes);

  /// Announces us on Presence as being on the canvas.
  Future<void>          enterCanvas(String coupleId, String userId);
  /// Back to plain Presence once we leave the canvas.
  Future<void>          leaveCanvas(String coupleId, String userId);
  /// Whether the partner is on the canvas right now, with every change.
  Stream<bool>          watchPartnerOnCanvas(String coupleId, String partnerUserId);
}
