import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/crypto/content_cipher.dart';
import '../../../../core/utils/geo_util.dart';
import '../../../../domain/entities/couple.dart';
import '../../../../domain/entities/shared_location.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_location_repository.dart';

part 'long_distance_event.dart';
part 'long_distance_state.dart';

class LongDistanceBloc extends Bloc<LongDistanceEvent, LongDistanceState> {
  LongDistanceBloc({required this.coupleRepository, required this.locationRepository})
      : super(const LongDistanceState()) {
    on<LongDistanceStarted>(_onStarted);
    on<_CoupleChanged>(_onCoupleChanged);
    on<_PartnerLocationChanged>(_onPartnerLocation);
    on<NextMeetChosen>(_onNextMeetChosen);
  }

  final ICoupleRepository   coupleRepository;
  final ILocationRepository locationRepository;

  String _coupleId = '', _userId = '', _partnerId = '';
  SharedLocation? _own, _partner;
  StreamSubscription<Couple>?          _coupleSub;
  StreamSubscription<SharedLocation?>? _partnerSub;

  Future<void> _onStarted(LongDistanceStarted e, Emitter<LongDistanceState> emit) async {
    _coupleId  = e.coupleId;
    _userId    = e.userId;
    _partnerId = e.partnerId;

    try {
      final couple = await coupleRepository.getCouple(_coupleId);
      emit(_stateFor(couple));
    } catch (_) {
      return; // offline with nothing saved: the card stays hidden
    }
    // Live updates: the partner may switch the mode or set the date on their phone.
    await _coupleSub?.cancel();
    _coupleSub = coupleRepository.watchCouple(_coupleId).listen((c) { if (!isClosed) add(_CoupleChanged(c)); });

    // Our own saved row is readable like the partner's; both are needed for a distance.
    try {
      _own = await locationRepository.getPartnerLocation(_userId);
    } catch (_) {}
    await _partnerSub?.cancel();
    _partnerSub = locationRepository
        .watchPartnerLocation(_partnerId)
        .listen((l) { if (!isClosed) add(_PartnerLocationChanged(l)); }, onError: (_) {});
  }

  Couple? _couple;

  LongDistanceState _stateFor(Couple couple, {String? error}) {
    _couple = couple;
    final own = _own, partner = _partner;
    return LongDistanceState(
      visible:        couple.relationshipMode == RelationshipMode.longDistance,
      distanceMetres: own == null || partner == null
          ? null
          : GeoUtil.distanceMetres(own.latitude, own.longitude, partner.latitude, partner.longitude),
      nextMeetOn:     couple.nextMeetOn,
      error:          error,
    );
  }

  void _onCoupleChanged(_CoupleChanged e, Emitter<LongDistanceState> emit) => emit(_stateFor(e.couple));

  void _onPartnerLocation(_PartnerLocationChanged e, Emitter<LongDistanceState> emit) {
    _partner = e.location;
    final couple = _couple;
    if (couple != null) emit(_stateFor(couple));
  }

  Future<void> _onNextMeetChosen(NextMeetChosen e, Emitter<LongDistanceState> emit) async {
    final couple = _couple;
    if (couple == null) return;
    try {
      await coupleRepository.setNextMeet(_coupleId, _userId, e.day);
      emit(_stateFor((await coupleRepository.getCouple(_coupleId))));
    } on EncryptionNotReady catch (err) {
      emit(_stateFor(couple, error: err.message));
    } catch (_) {
      emit(_stateFor(couple, error: 'Could not save the date. Check your connection.'));
    }
  }

  @override
  Future<void> close() {
    _coupleSub?.cancel();
    _partnerSub?.cancel();
    return super.close();
  }
}
