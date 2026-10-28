part of 'canvas_bloc.dart';

enum CanvasTool { pen, eraser }

class CanvasState {
  const CanvasState({
    this.strokes       = const [],
    this.remoteStrokes = const [],
    this.committed     = const [],
    this.activeStroke,
    this.activeColor   = const Color(0xFFFF6EC7),
    this.activeTool    = CanvasTool.pen,
    this.isSaving      = false,
    this.saveFailed    = false,
    this.saveQueued    = false,
    this.partnerHere   = false,
    this.isReady       = false,
    this.needsSecuring = false,
    this.hasUnreadable = false,
  });

  final List<CanvasStroke> strokes;
  final List<CanvasStroke> remoteStrokes;

  /// [strokes] + [remoteStrokes] in drawing order (by timestamp). Rebuilt only
  /// when either list changes, so per-point updates don't re-sort.
  final List<CanvasStroke> committed;
  final CanvasStroke?      activeStroke;
  final Color              activeColor;
  final CanvasTool         activeTool;
  final bool               isSaving;
  /// The last save did not complete; reset when the next one starts.
  final bool               saveFailed;
  /// The last save was kept on the device (no connection) and will be sent later.
  final bool               saveQueued;
  /// The partner is on the canvas right now (from Presence).
  final bool               partnerHere;

  /// True once the couple is resolved and sync is running.
  final bool               isReady;

  /// This phone has no couple key yet, so nothing can be drawn: the connection is not secured.
  final bool               needsSecuring;

  /// Strokes were saved that this phone cannot read (it probably does not hold the same couple key).
  final bool               hasUnreadable;

  static List<CanvasStroke> _merge(List<CanvasStroke> a, List<CanvasStroke> b) =>
      [...a, ...b]..sort((x, y) {
        final c = x.timestamp.compareTo(y.timestamp);
        return c != 0 ? c : x.id.compareTo(y.id);
      });

  CanvasState copyWith({
    List<CanvasStroke>? strokes,
    List<CanvasStroke>? remoteStrokes,
    CanvasStroke?       activeStroke,
    bool                clearActive = false,
    Color?              activeColor,
    CanvasTool?         activeTool,
    bool?               isSaving,
    bool?               saveFailed,
    bool?               saveQueued,
    bool?               partnerHere,
    bool?               isReady,
    bool?               needsSecuring,
    bool?               hasUnreadable,
  }) {
    final newStrokes = strokes       ?? this.strokes;
    final newRemote  = remoteStrokes ?? this.remoteStrokes;
    final listsChanged = strokes != null || remoteStrokes != null;
    return CanvasState(
      strokes:       newStrokes,
      remoteStrokes: newRemote,
      committed:     listsChanged ? _merge(newStrokes, newRemote) : committed,
      activeStroke:  clearActive ? null : (activeStroke ?? this.activeStroke),
      activeColor:   activeColor ?? this.activeColor,
      activeTool:    activeTool  ?? this.activeTool,
      isSaving:      isSaving    ?? this.isSaving,
      saveFailed:    saveFailed  ?? this.saveFailed,
      saveQueued:    saveQueued  ?? this.saveQueued,
      partnerHere:   partnerHere ?? this.partnerHere,
      isReady:       isReady     ?? this.isReady,
      needsSecuring: needsSecuring ?? this.needsSecuring,
      hasUnreadable: hasUnreadable ?? this.hasUnreadable,
    );
  }
}
