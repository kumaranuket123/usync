import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/couple.dart';
import '../../../../domain/entities/user.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../domain/repositories/i_couple_repository.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  ProfileBloc({
    required this.authRepository,
    required this.coupleRepository,
  }) : super(ProfileLoading()) {
    on<ProfileLoaded>(_onLoaded);
    on<DisconnectRequested>(_onDisconnectRequested);
    on<DisconnectCancelled>(_onDisconnectCancelled);
    on<DisconnectConfirmed>(_onDisconnectConfirmed);
    on<CoupleUpdated>(_onCoupleUpdated);
    on<UserUpdated>((e, emit) {
      final current = state;
      if (current is ProfileReady) emit(ProfileReady(user: e.user, couple: current.couple));
    });
  }

  final IAuthRepository   authRepository;
  final ICoupleRepository coupleRepository;

  StreamSubscription<Couple>? _coupleSub;

  Future<void> _onLoaded(ProfileLoaded e, Emitter<ProfileState> emit) async {
    if (e.coupleId.isEmpty || e.userId.isEmpty) { emit(ProfileError('Not paired')); return; }
    emit(ProfileLoading());
    try {
      final results = await Future.wait([
        authRepository.getCurrentUser(),
        coupleRepository.getCouple(e.coupleId),
      ]);
      emit(ProfileReady(
        user:   results[0] as AppUser,
        couple: results[1] as Couple,
      ));
      _coupleSub?.cancel();
      _coupleSub = coupleRepository.watchCouple(e.coupleId).listen((c) => add(CoupleUpdated(c)));
    } catch (err) {
      emit(ProfileError(err.toString()));
    }
  }

  void _onCoupleUpdated(CoupleUpdated e, Emitter<ProfileState> emit) {
    final current = state;
    if (e.couple.isDisconnected) {
      emit(ProfileDisconnected());
    } else if (current is ProfileReady) {
      emit(ProfileReady(user: current.user, couple: e.couple));
    }
  }

  Future<void> _onDisconnectRequested(DisconnectRequested e, Emitter<ProfileState> emit) =>
      _run(emit, () => coupleRepository.requestDisconnect(e.coupleId, e.userId));

  Future<void> _onDisconnectCancelled(DisconnectCancelled e, Emitter<ProfileState> emit) =>
      _run(emit, () => coupleRepository.cancelDisconnect(e.coupleId));

  Future<void> _onDisconnectConfirmed(DisconnectConfirmed e, Emitter<ProfileState> emit) =>
      _run(emit, () => coupleRepository.confirmDisconnect(e.coupleId, e.userId));

  /// Runs a disconnect step; the couple stream drives the resulting state.
  Future<void> _run(Emitter<ProfileState> emit, Future<void> Function() action) async {
    final previous = state;
    try {
      await action();
    } catch (err) {
      emit(ProfileError(err.toString()));
      if (previous is ProfileReady) emit(previous);
    }
  }

  @override
  Future<void> close() {
    _coupleSub?.cancel();
    return super.close();
  }
}
