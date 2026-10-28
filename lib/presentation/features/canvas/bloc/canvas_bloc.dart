import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/crypto/content_cipher.dart';
import '../../../../core/services/home_widget_service.dart';
import '../../../../domain/entities/canvas_stroke.dart';
import '../../../../domain/repositories/i_canvas_repository.dart';
import '../../../../domain/repositories/i_memory_repository.dart';

part 'canvas_event.dart';
part 'canvas_state.dart';

class CanvasBloc extends Bloc<CanvasEvent, CanvasState> {
  CanvasBloc({required this.canvasRepository, required this.memoryRepository}) : super(const CanvasState()) {
    on<CanvasMounted>(_onMounted);
    on<StrokeStarted>(_onStart);
    on<StrokeUpdated>(_onUpdate);
    on<StrokeEnded>(_onEnd);
    on<_FlushRequested>((_, __) => _flush());
    on<ColorChanged>((e, emit) => emit(state.copyWith(activeColor: e.color, activeTool: CanvasTool.pen)));
    on<ToolChanged>((e, emit)  => emit(state.copyWith(activeTool: e.tool)));
    on<CanvasCleared>(_onClear);
    on<MemorySaved>(_onSave);
    on<StrokesFlushRequested>((_, __) => _guard(canvasRepository.flushStrokes()));
    on<PartnerHereChanged>((e, emit) => emit(state.copyWith(partnerHere: e.isHere)));
    on<RemoteStrokeReceived>(_onRemote);
    on<StrokesUnreadableDetected>((_, emit) => emit(state.copyWith(hasUnreadable: true)));
    on<RemoteCanvasCleared>(
      (_, emit) => emit(state.copyWith(strokes: [], remoteStrokes: [], clearActive: true)),
    );
  }

  /// How often points drawn since the last write are sent to the partner.
  static const _flushInterval = Duration(milliseconds: 150);

  final ICanvasRepository       canvasRepository;
  final IMemoryRepository       memoryRepository;
  StreamSubscription<CanvasStroke>? _remoteSub;
  StreamSubscription<int>?          _clearSub;
  StreamSubscription<bool>?         _presenceSub;
  Timer?  _flushTimer;
  Timer?  _widgetTimer;
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
    await _presenceSub?.cancel();

    // Tell the partner we are here, and watch for them.
    canvasRepository.enterCanvas(_coupleId, _userId).ignore();
    _presenceSub = canvasRepository.watchPartnerOnCanvas(_coupleId, e.partnerUserId).listen(
      (here) { if (!isClosed) add(PartnerHereChanged(here)); },
      onError: (Object err) => debugPrint('Canvas presence error: $err'),
    );

    _remoteSub = canvasRepository.watchRemoteStrokes(_coupleId, _userId).listen(
      (stroke) { if (!isClosed) add(RemoteStrokeReceived(stroke)); },
      onError: (Object err) {
        debugPrint('Canvas stroke stream error: $err');
        if (err is StrokesUnreadable && !isClosed) add(StrokesUnreadableDetected());
      },
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

    // The drawing is sealed on this phone; without the couple key nothing is drawn (or sent) readable.
    final secured = await canvasRepository.isReady(_coupleId);
    emit(state.copyWith(isReady: secured, needsSecuring: !secured));
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
    if (state.isSaving) return;
    emit(state.copyWith(isSaving: true, saveFailed: false, saveQueued: false));
    try {
      // Uploads the picture and saves the memory (which notifies the partner);
      // without a connection both wait on the device and are sent later.
      final sentNow = await memoryRepository.saveDoodle(
        coupleId: _coupleId,
        userId:   _userId,
        png:      e.imageBytes,
        title:    'Doodle · ${DateFormat('d MMM, h:mm a').format(DateTime.now())}',
      );
      emit(state.copyWith(isSaving: false, saveQueued: !sentNow));
    } catch (err) {
      debugPrint('Canvas save failed: $err');
      emit(state.copyWith(isSaving: false, saveFailed: true, needsSecuring: err is EncryptionNotReady ? true : null));
    }
  }

  void _onRemote(RemoteStrokeReceived e, Emitter<CanvasState> emit) {
    // Our own strokes come back from the saved history when the canvas is reopened.
    if (e.stroke.userId == _userId) {
      if (state.strokes.any((s) => s.id == e.stroke.id)) return;
      emit(state.copyWith(strokes: [...state.strokes, e.stroke]));
      return;
    }
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

  /// The shared drawing changed (by either of us): redraw this phone's home-screen
  /// widget once things settle, rather than on every stroke chunk.
  @override
  void onChange(Change<CanvasState> change) {
    super.onChange(change);
    if (identical(change.currentState.committed, change.nextState.committed)) return;
    final committed = change.nextState.committed;
    _widgetTimer?.cancel();
    _widgetTimer = Timer(const Duration(seconds: 2), () => HomeWidgetService.refresh(committed));
  }

  @override
  Future<void> close() {
    _flushTimer?.cancel();
    _remoteSub?.cancel();
    _clearSub?.cancel();
    _presenceSub?.cancel();
    canvasRepository.flushStrokes().ignore();
    if (_coupleId.isNotEmpty) canvasRepository.leaveCanvas(_coupleId, _userId).ignore();
    return super.close();
  }
}
