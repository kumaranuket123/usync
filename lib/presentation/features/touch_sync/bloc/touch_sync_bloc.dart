import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/haptic_util.dart';
import '../../../../domain/repositories/i_touch_repository.dart';

part 'touch_sync_event.dart';
part 'touch_sync_state.dart';

class TouchSyncBloc extends Bloc<TouchSyncEvent, TouchSyncState> {
  TouchSyncBloc({required this.touchRepository}) : super(TouchSyncConnecting()) {
    on<TouchScreenMounted>(_onMounted);
    on<TouchPressed>(_onPressed);
    on<TouchReleased>(_onReleased);
    on<RemoteTouchReceived>(_onRemote);
    on<ConnectionLost>((_, emit) =>
        emit(TouchSyncReady(isConnected: false)));
  }

  final ITouchRepository touchRepository;
  StreamSubscription<bool>? _sub;
  Timer?    _hapticTimer;
  String    _coupleId  = '';
  String    _userId    = '';
  String    _partnerId = '';

  Future<void> _onMounted(TouchScreenMounted e, Emitter<TouchSyncState> emit) async {
    _coupleId  = e.coupleId;
    _userId    = e.userId;
    _partnerId = e.partnerUserId;

    await touchRepository.registerDisconnectClear(_coupleId, _userId);
    _sub = touchRepository
        .watchPartnerTouch(_coupleId, _partnerId)
        .listen((active) { if (!isClosed) add(RemoteTouchReceived(active)); });

    emit(TouchSyncReady());
  }

  Future<void> _onPressed(TouchPressed _, Emitter<TouchSyncState> emit) async {
    await touchRepository.setTouchActive(_coupleId, _userId, isActive: true);
    await HapticUtil.heavy();
    if (state is TouchSyncReady) {
      emit((state as TouchSyncReady).copyWith(isOwnerTouching: true));
    }
  }

  Future<void> _onReleased(TouchReleased _, Emitter<TouchSyncState> emit) async {
    await touchRepository.setTouchActive(_coupleId, _userId, isActive: false);
    await HapticUtil.light();
    if (state is TouchSyncReady) {
      emit((state as TouchSyncReady).copyWith(isOwnerTouching: false));
    }
  }

  Future<void> _onRemote(RemoteTouchReceived e, Emitter<TouchSyncState> emit) async {
    if (state is TouchSyncReady) {
      emit((state as TouchSyncReady).copyWith(isPartnerTouching: e.isActive));
    }
    if (e.isActive) {
      await HapticUtil.touchLanding();
      _hapticTimer = Timer.periodic(
        const Duration(milliseconds: 1200),
        (_) => HapticUtil.touchPulse(),
      );
    } else {
      _hapticTimer?.cancel();
      _hapticTimer = null;
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    _hapticTimer?.cancel();
    touchRepository.setTouchActive(_coupleId, _userId, isActive: false);
    return super.close();
  }
}
