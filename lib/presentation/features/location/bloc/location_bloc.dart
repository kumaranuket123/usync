import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/shared_location.dart';
import '../../../../domain/repositories/i_location_repository.dart';

part 'location_event.dart';
part 'location_state.dart';

class LocationBloc extends Bloc<LocationEvent, LocationState> {
  LocationBloc({required this.locationRepository}) : super(LocationConnecting()) {
    on<LocationScreenMounted>(_onMounted);
    on<LocationSharingToggled>(_onToggled);
    on<LocationRefreshed>(_onRefreshed);
    on<LocateRequested>(_onLocate);
    on<BackgroundToggled>(_onBackgroundToggled);
    on<PartnerLocationChanged>(_onPartnerChanged);
    on<LocationSettingsRequested>(_onSettings);
  }

  final ILocationRepository locationRepository;
  String _coupleId = '', _userId = '', _partnerId = '';
  StreamSubscription<SharedLocation?>? _partnerSub;
  Timer? _locateTimeout;

  /// How long to wait for the partner's phone before giving up on a request.
  static const _locateWait = Duration(seconds: 45);

  Future<void> _onMounted(LocationScreenMounted e, Emitter<LocationState> emit) async {
    _coupleId  = e.coupleId;
    _userId    = e.userId;
    _partnerId = e.partnerUserId;

    final sharing = locationRepository.sharingEnabled;
    // Let the partner know we looked; it never blocks or fails the screen.
    locationRepository.notifyPartnerViewing(_coupleId, _userId).ignore();

    // One subscription gives the partner's position now and every later change
    // (including a requested fix), so there is no separate read first.
    final firstPartner = Completer<SharedLocation?>();
    await _partnerSub?.cancel();
    _partnerSub = locationRepository.watchPartnerLocation(_partnerId).listen(
      (l) {
        if (!firstPartner.isCompleted) firstPartner.complete(l);
        if (!isClosed) add(PartnerLocationChanged(l));
      },
      onError: (_) {},
    );

    final results = await Future.wait<Object?>([
      firstPartner.future.timeout(const Duration(seconds: 5), onTimeout: () => null),
      if (sharing) _sync(prompt: false),
    ]);
    final partner = results[0] as SharedLocation?;
    final sync    = sharing ? results[1] as SyncResult? : null;

    emit(LocationReady(
      isSharing: sharing,
      own:       sync?.location,
      partner:   partner,
      access:    sync?.access ?? LocationAccess.granted,
    ));
  }

  void _onPartnerChanged(PartnerLocationChanged e, Emitter<LocationState> emit) {
    final current = state;
    if (current is! LocationReady) return;
    // A newer timestamp than the one we had means the request was answered.
    final answered = e.location != null &&
        (current.partner == null || e.location!.timestamp.isAfter(current.partner!.timestamp));
    if (answered) _locateTimeout?.cancel();
    emit(current.copyWith(
      partner:    () => e.location,
      isLocating: answered ? false : current.isLocating,
    ));
  }

  Future<void> _onLocate(LocateRequested _, Emitter<LocationState> emit) async {
    final current = state;
    if (current is! LocationReady || current.isLocating) return;
    emit(current.copyWith(isLocating: true));
    await locationRepository.requestPartnerLocation(_coupleId, _userId);
    _locateTimeout?.cancel();
    _locateTimeout = Timer(_locateWait, () { if (!isClosed) add(LocationRefreshed()); });
  }

  Future<void> _onBackgroundToggled(BackgroundToggled _, Emitter<LocationState> emit) async {
    final current = state;
    if (current is! LocationReady || current.isBusy || current.own == null) return;
    emit(current.copyWith(isBusy: true));

    if (current.own!.allowsBackground) {
      await locationRepository.disableBackground(_userId);
      emit(current.copyWith(isBusy: false, own: () => _withBackground(current.own!, false)));
      return;
    }
    final access = await locationRepository.enableBackground(_userId);
    final granted = access == LocationAccess.granted;
    emit(current.copyWith(
      isBusy: false,
      access: access,
      own:    granted ? () => _withBackground(current.own!, true) : null,
    ));
  }

  static SharedLocation _withBackground(SharedLocation l, bool allow) => SharedLocation(
        latitude:         l.latitude,
        longitude:        l.longitude,
        accuracy:         l.accuracy,
        timestamp:        l.timestamp,
        allowsBackground: allow,
      );

  Future<void> _onToggled(LocationSharingToggled _, Emitter<LocationState> emit) async {
    final current = state;
    if (current is! LocationReady || current.isBusy) return;

    if (current.isSharing) {
      emit(current.copyWith(isBusy: true));
      await locationRepository.setSharingEnabled(false);
      try { await locationRepository.clearOwnLocation(_userId); } catch (_) {}
      emit(LocationReady(partner: current.partner));
      return;
    }

    emit(current.copyWith(isBusy: true));
    final sync = await _sync(prompt: true);
    if (sync == null || sync.access != LocationAccess.granted) {
      emit(current.copyWith(isBusy: false, access: sync?.access ?? current.access));
      return;
    }
    await locationRepository.setSharingEnabled(true);
    emit(current.copyWith(
      isSharing: true,
      isBusy:    false,
      own:       () => sync.location,
      access:    LocationAccess.granted,
    ));
  }

  Future<void> _onRefreshed(LocationRefreshed _, Emitter<LocationState> emit) async {
    final current = state;
    if (current is! LocationReady || current.isBusy) return;
    emit(current.copyWith(isBusy: true));
    final partner = await _loadPartner();
    emit(current.copyWith(isBusy: false, isLocating: false, partner: () => partner));
  }

  Future<void> _onSettings(LocationSettingsRequested _, Emitter<LocationState> emit) async {
    final current = state;
    if (current is LocationReady) await locationRepository.openSettings(current.access);
  }

  Future<SharedLocation?> _loadPartner() async {
    try {
      return await locationRepository.getPartnerLocation(_partnerId);
    } catch (_) {
      return null;
    }
  }

  Future<SyncResult?> _sync({required bool prompt}) async {
    try {
      return await locationRepository.syncOwnLocation(_coupleId, _userId, prompt: prompt);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() {
    _partnerSub?.cancel();
    _locateTimeout?.cancel();
    return super.close();
  }
}
