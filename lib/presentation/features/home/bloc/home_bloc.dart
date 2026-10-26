import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/couple.dart';
import '../../../../domain/entities/mood.dart';
import '../../../../domain/entities/user.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_mood_repository.dart';

part 'home_event.dart';
part 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc({
    required this.authRepository,
    required this.coupleRepository,
    required this.moodRepository,
  }) : super(HomeLoading()) {
    on<HomeStarted>(_onStarted);
    on<PartnerPresenceUpdated>(_onPresence);
    on<RecentMoodsRefreshed>(_onMoodsRefreshed);
  }

  final IAuthRepository   authRepository;
  final ICoupleRepository coupleRepository;
  final IMoodRepository   moodRepository;

  StreamSubscription<bool>?        _presenceSub;
  StreamSubscription<List<Mood>>?  _moodsSub;
  String _partnerId = '';

  static Mood? _latestFrom(List<Mood> moods, String userId) {
    for (final m in moods) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  Future<void> _onStarted(HomeStarted _, Emitter<HomeState> emit) async {
    emit(HomeLoading());
    try {
      // 1. Get current user
      final user = await authRepository.getCurrentUser();
      if (user == null) { emit(HomeError('Not authenticated')); return; }

      final coupleId = user.coupleId;
      if (coupleId == null) { emit(HomeError('Not paired yet')); return; }

      // 2. Get couple + partner in parallel
      final couple = await coupleRepository.getCouple(coupleId);
      final partnerId = couple.partnerIdFor(user.id);

      final partner = await authRepository.getUserById(partnerId) ??
          AppUser(
            id:          partnerId,
            username:    'Partner',
            email:       '',
            avatarEmoji: '🌙',
            createdAt:   DateTime.now(),
          );

      // 3. Moods: one stream gives both the recent list and the partner's
      //    current mood. Wait briefly for the first value (the saved copy
      //    arrives at once; with neither, Home opens without moods).
      _partnerId = partnerId;
      final firstMoods = Completer<List<Mood>>();
      await _moodsSub?.cancel();
      _moodsSub = moodRepository.watchRecentMoods(coupleId).listen((moods) {
        if (!firstMoods.isCompleted) firstMoods.complete(moods);
        if (!isClosed) add(RecentMoodsRefreshed(moods));
      });
      final recentMoods = await firstMoods.future
          .timeout(const Duration(seconds: 5), onTimeout: () => const <Mood>[]);

      // 4. Emit loaded
      emit(HomeLoaded(
        user:        user,
        partner:     partner,
        couple:      couple,
        partnerMood: _latestFrom(recentMoods, partnerId),
        recentMoods: recentMoods,
      ));

      // 5. Live presence
      _presenceSub?.cancel();
      _presenceSub = coupleRepository
          .watchPartnerPresence(coupleId, partnerId)
          .listen((isOnline) { if (!isClosed) add(PartnerPresenceUpdated(isOnline)); });

      // 6. Keep presence updated
      await coupleRepository.updatePresence(coupleId, user.id, isOnline: true);

    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }

  void _onPresence(PartnerPresenceUpdated e, Emitter<HomeState> emit) {
    if (state is HomeLoaded) {
      emit((state as HomeLoaded).copyWith(isOnline: e.isOnline));
    }
  }

  void _onMoodsRefreshed(RecentMoodsRefreshed e, Emitter<HomeState> emit) {
    if (state is HomeLoaded) {
      emit((state as HomeLoaded).copyWith(
        recentMoods: e.moods,
        partnerMood: _latestFrom(e.moods, _partnerId),
      ));
    }
  }

  @override
  Future<void> close() {
    _presenceSub?.cancel();
    _moodsSub?.cancel();
    return super.close();
  }
}
