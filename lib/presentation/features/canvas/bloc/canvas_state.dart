part of 'canvas_bloc.dart';

enum CanvasTool { pen, eraser }

class CanvasState {
  const CanvasState({
    this.strokes       = const [],
    this.remoteStrokes = const [],
    this.activeStroke,
    this.activeColor   = const Color(0xFFFF6EC7),
    this.activeTool    = CanvasTool.pen,
    this.isSaving      = false,
  });

  final List<CanvasStroke> strokes;
  final List<CanvasStroke> remoteStrokes;
  final CanvasStroke?      activeStroke;
  final Color              activeColor;
  final CanvasTool         activeTool;
  final bool               isSaving;

  List<CanvasStroke> get allStrokes => [...strokes, ...remoteStrokes, if (activeStroke != null) activeStroke!];

  CanvasState copyWith({
    List<CanvasStroke>? strokes,
    List<CanvasStroke>? remoteStrokes,
    CanvasStroke?       activeStroke,
    bool                clearActive = false,
    Color?              activeColor,
    CanvasTool?         activeTool,
    bool?               isSaving,
  }) => CanvasState(
    strokes:       strokes       ?? this.strokes,
    remoteStrokes: remoteStrokes ?? this.remoteStrokes,
    activeStroke:  clearActive   ? null : (activeStroke ?? this.activeStroke),
    activeColor:   activeColor   ?? this.activeColor,
    activeTool:    activeTool    ?? this.activeTool,
    isSaving:      isSaving      ?? this.isSaving,
  );
}
