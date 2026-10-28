import 'dart:ui';

import '../entities/canvas_stroke.dart';

/// Reported (once) on [ICanvasRepository.watchRemoteStrokes] when strokes were saved but this phone cannot
/// read them, usually because it does not hold the same couple key as the partner's phone.
class StrokesUnreadable implements Exception {
  const StrokesUnreadable();

  @override
  String toString() => 'Some of the drawing cannot be read on this phone';
}

abstract interface class ICanvasRepository {
  /// Creates the stroke node (metadata only, `isComplete: false`).
  Future<void>          pushStroke(CanvasStroke stroke);

  /// Appends a batch of points so the partner sees the stroke while it is drawn.
  /// [seq] orders chunks within the stroke.
  Future<void>          pushStrokeChunk(String coupleId, String strokeId, int seq, List<Offset> points);
  Future<void>          completeStroke(String coupleId, String strokeId);

  /// Finished strokes are saved in small batches rather than one request each;
  /// this sends whatever is waiting now (when leaving the canvas or the app).
  Future<void>          flushStrokes();
  Stream<CanvasStroke>  watchRemoteStrokes(String coupleId, String excludeUserId);

  /// Whether this phone has the couple key, so the drawing can be sealed. Without it nothing is drawn.
  Future<bool>          isReady(String coupleId);

  /// Removes all strokes and returns the clear timestamp written for the partner.
  Future<int>           clearCanvas(String coupleId);

  /// Emits the current `clearedAt` timestamp (0 if never cleared), then every change.
  Stream<int>           watchCanvasCleared(String coupleId);

  /// Announces us on Presence as being on the canvas.
  Future<void>          enterCanvas(String coupleId, String userId);
  /// Back to plain Presence once we leave the canvas.
  Future<void>          leaveCanvas(String coupleId, String userId);
  /// Whether the partner is on the canvas right now, with every change.
  Stream<bool>          watchPartnerOnCanvas(String coupleId, String partnerUserId);
}
