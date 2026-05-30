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
    on<ColorChanged>((e, emit) => emit(state.copyWith(activeColor: e.color, activeTool: CanvasTool.pen)));
    on<ToolChanged>((e, emit)  => emit(state.copyWith(activeTool: e.tool)));
    on<CanvasCleared>(_onClear);
    on<MemorySaved>(_onSave);
    on<RemoteStrokeReceived>(_onRemote);
    on<RemoteCanvasCleared>((_, emit) => emit(const CanvasState()));
  }

  final ICanvasRepository       canvasRepository;
  StreamSubscription<CanvasStroke>? _remoteSub;
  StreamSubscription<void>?         _clearSub;
  String _coupleId = '';
  String _userId   = '';
  final _uuid = const Uuid();

  Future<void> _onMounted(CanvasMounted e, Emitter<CanvasState> emit) async {
    _coupleId = e.coupleId;
    _userId   = e.userId;

    _remoteSub = canvasRepository
        .watchRemoteStrokes(_coupleId, _userId)
        .listen((stroke) { if (!isClosed) add(RemoteStrokeReceived(stroke)); });

    _clearSub = canvasRepository
        .watchCanvasCleared(_coupleId)
        .listen((_) { if (!isClosed) add(RemoteCanvasCleared()); });
  }

  void _onStart(StrokeStarted e, Emitter<CanvasState> emit) {
    // No RTDB write here — collect points locally until finger lifts.
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
  }

  void _onUpdate(StrokeUpdated e, Emitter<CanvasState> emit) {
    // No RTDB write — append to local active stroke only.
    if (state.activeStroke == null) return;
    emit(state.copyWith(activeStroke: state.activeStroke!.appendPoint(e.offset)));
  }

  Future<void> _onEnd(StrokeEnded _, Emitter<CanvasState> emit) async {
    if (state.activeStroke == null) return;
    final completed = state.activeStroke!.complete();
    emit(state.copyWith(strokes: [...state.strokes, completed], clearActive: true));
    // Push the complete stroke with all points in a single RTDB call.
    if (_coupleId.isNotEmpty) {
      canvasRepository.pushCompleteStroke(completed);
    }
  }

  Future<void> _onClear(CanvasCleared _, Emitter<CanvasState> emit) async {
    await canvasRepository.clearCanvas(_coupleId);
    emit(const CanvasState());
  }

  Future<void> _onSave(MemorySaved e, Emitter<CanvasState> emit) async {
    emit(state.copyWith(isSaving: true));
    await canvasRepository.saveCanvasBitmap(_coupleId, e.imageBytes);
    emit(state.copyWith(isSaving: false));
  }

  void _onRemote(RemoteStrokeReceived e, Emitter<CanvasState> emit) {
    final current = List<CanvasStroke>.from(state.remoteStrokes);
    final idx     = current.indexWhere((s) => s.id == e.stroke.id);
    if (idx >= 0) {
      current[idx] = e.stroke;
    } else {
      current.add(e.stroke);
    }
    emit(state.copyWith(remoteStrokes: current));
  }

  @override
  Future<void> close() {
    _remoteSub?.cancel();
    _clearSub?.cancel();
    return super.close();
  }
}
