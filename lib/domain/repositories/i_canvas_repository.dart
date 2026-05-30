import 'dart:typed_data';

import '../entities/canvas_stroke.dart';

abstract interface class ICanvasRepository {
  Future<void>          pushStroke(CanvasStroke stroke);           // legacy — kept for compat
  Future<void>          pushStrokePoint(String coupleId, String strokeId, double x, double y);
  Future<void>          completeStroke(String coupleId, String strokeId);
  Future<void>          pushCompleteStroke(CanvasStroke stroke);  // writes full stroke in one call
  Stream<CanvasStroke>  watchRemoteStrokes(String coupleId, String excludeUserId);
  Future<void>          clearCanvas(String coupleId);
  Stream<void>          watchCanvasCleared(String coupleId);
  Future<String>        saveCanvasBitmap(String coupleId, Uint8List bytes);
}
