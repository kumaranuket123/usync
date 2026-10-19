import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../domain/entities/canvas_stroke.dart';
import '../../../../domain/repositories/i_canvas_repository.dart';

part 'canvas_event.dart';
part 'canvas_state.dart';

class CanvasBloc extends Bloc<CanvasEvent, CanvasState> {
  CanvasBloc({required this.canvasRepository}) : super(const CanvasState()) {
    on<CanvasMounted>(_onMounted);
    on<StrokeStarted>(_onStart);
    on<StrokeUpdated>(_onUpdate);
    on<StrokeEnded>(_onEnd);
    on<_FlushRequested>((_, __) => _flush());
    on<ColorChanged>((e, emit) => emit(state.copyWith(activeColor: e.color, activeTool: CanvasTool.pen)));
    on<ToolChanged>((e, emit)  => emit(state.copyWith(activeTool: e.tool)));
    on<CanvasCleared>(_onClear);
    on<MemorySaved>(_onSave);
    on<RemoteStrokeReceived>(_onRemote);
    on<RemoteCanvasCleared>(
      (_, emit) => emit(state.copyWith(strokes: [], remoteStrokes: [], clearActive: true)),
    );
  }

  /// How often points drawn since the last write are sent to the partner.
  static const _flushInterval = Duration(milliseconds: 80);

  final ICanvasRepository       canvasRepository;
  StreamSubscription<CanvasStroke>? _remoteSub;
  StreamSubscription<int>?          _clearSub;
  Timer?  _flushTimer;
  final   _pending = <Offset>[];
  int     _seq = 0;
  int?    _clearedAt; // null until the first value arrives (the baseline)
  String _coupleId = '';
  String _userId   = '';
  final _uuid = const Uuid();

  Future<void> _onMounted(CanvasMounted e, Emitter<CanvasState> emit) async {
    _coupleId = e.coupleId;
    _userId   = e.userId;

    await _remoteSub?.cancel();
    await _clearSub?.cancel();

    _remoteSub = canvasRepository.watchRemoteStrokes(_coupleId, _userId).listen(
      (stroke) { if (!isClosed) add(RemoteStrokeReceived(stroke)); },
      onError: (Object err) => debugPrint('Canvas stroke stream error: $err'),
    );

    // The first value is the existing clearedAt (or 0), which is only a baseline —
    // treating it as a clear would wipe strokes that were just replayed.
    _clearSub = canvasRepository.watchCanvasCleared(_coupleId).listen(
      (ts) {
        final baseline = _clearedAt;
        _clearedAt = ts;
        if (baseline != null && ts != baseline && !isClosed) add(RemoteCanvasCleared());
      },
      onError: (Object err) => debugPrint('Canvas clear stream error: $err'),
    );

    emit(state.copyWith(isReady: true));
  }

  void _onStart(StrokeStarted e, Emitter<CanvasState> emit) {
    if (!state.isReady) return;
    final stroke = CanvasStroke(
      id:        _uuid.v4(),
      coupleId:  _coupleId,
      userId:    _userId,
      color:     state.activeColor,
      width:     state.activeTool == CanvasTool.eraser ? 30.0 : 3.0,
      isEraser:  state.activeTool == CanvasTool.eraser,
      timestamp: DateTime.now(),
      points:    [e.offset],
    );
    emit(state.copyWith(activeStroke: stroke));

    _pending..clear()..add(e.offset);
    _seq = 0;
    _guard(canvasRepository.pushStroke(stroke));
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) {
      if (!isClosed) add(_FlushRequested());
    });
  }

  void _onUpdate(StrokeUpdated e, Emitter<CanvasState> emit) {
    final active = state.activeStroke;
    if (active == null) return;
    _pending.add(e.offset);
    emit(state.copyWith(activeStroke: active.appendPoint(e.offset)));
  }

  Future<void> _onEnd(StrokeEnded _, Emitter<CanvasState> emit) async {
    final active = state.activeStroke;
    if (active == null) return;
    _flushTimer?.cancel();
    _flush(strokeId: active.id);
    final completed = active.complete();
    emit(state.copyWith(strokes: [...state.strokes, completed], clearActive: true));
    _guard(canvasRepository.completeStroke(_coupleId, completed.id));
  }

  /// Sends points collected since the last flush as one chunk.
  void _flush({String? strokeId}) {
    final id = strokeId ?? state.activeStroke?.id;
    if (id == null || _pending.isEmpty) return;
    final batch = List<Offset>.of(_pending);
    _pending.clear();
    _guard(canvasRepository.pushStrokeChunk(_coupleId, id, _seq++, batch));
  }

  Future<void> _onClear(CanvasCleared _, Emitter<CanvasState> emit) async {
    emit(state.copyWith(strokes: [], remoteStrokes: [], clearActive: true));
    try {
      // Remember our own timestamp so its echo isn't treated as a remote clear.
      _clearedAt = await canvasRepository.clearCanvas(_coupleId);
    } catch (err) {
      debugPrint('Canvas clear failed: $err');
    }
  }

  Future<void> _onSave(MemorySaved e, Emitter<CanvasState> emit) async {
    emit(state.copyWith(isSaving: true));
    await canvasRepository.saveCanvasBitmap(_coupleId, e.imageBytes);
    emit(state.copyWith(isSaving: false));
  }

  void _onRemote(RemoteStrokeReceived e, Emitter<CanvasState> emit) {
    final current = List<CanvasStroke>.of(state.remoteStrokes);
    final idx     = current.indexWhere((s) => s.id == e.stroke.id);
    if (idx >= 0) {
      current[idx] = e.stroke;
    } else {
      current.add(e.stroke);
    }
    emit(state.copyWith(remoteStrokes: current));
  }

  /// Network writes are fire-and-forget for the UI, but failures must not be
  /// silently lost as unhandled async errors.
  void _guard(Future<void> write) =>
      write.catchError((Object err) => debugPrint('Canvas write failed: $err'));

  @override
  Future<void> close() {
    _flushTimer?.cancel();
    _remoteSub?.cancel();
    _clearSub?.cancel();
    return super.close();
  }
}
