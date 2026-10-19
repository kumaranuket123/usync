part of 'canvas_bloc.dart';

sealed class CanvasEvent { const CanvasEvent(); }
final class CanvasMounted         extends CanvasEvent { CanvasMounted({required this.coupleId, required this.userId}); final String coupleId, userId; }
final class StrokeStarted         extends CanvasEvent { StrokeStarted(this.offset); final Offset offset; }
final class StrokeUpdated         extends CanvasEvent { StrokeUpdated(this.offset); final Offset offset; }
final class StrokeEnded           extends CanvasEvent {}
final class ColorChanged          extends CanvasEvent { ColorChanged(this.color); final Color color; }
final class ToolChanged           extends CanvasEvent { ToolChanged(this.tool); final CanvasTool tool; }
final class CanvasCleared         extends CanvasEvent {}
final class MemorySaved           extends CanvasEvent { MemorySaved(this.imageBytes); final Uint8List imageBytes; }
final class RemoteStrokeReceived  extends CanvasEvent { RemoteStrokeReceived(this.stroke); final CanvasStroke stroke; }
final class RemoteCanvasCleared   extends CanvasEvent {}
final class _FlushRequested       extends CanvasEvent {}
