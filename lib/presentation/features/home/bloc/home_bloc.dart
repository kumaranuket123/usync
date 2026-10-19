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
    on<PartnerMoodUpdated>(_onMood);
    on<RecentMoodsRefreshed>(_onMoodsRefreshed);
  }

  final IAuthRepository   authRepository;
  final ICoupleRepository coupleRepository;
  final IMoodRepository   moodRepository;

  StreamSubscription<bool>?  _presenceSub;
  StreamSubscription<Mood?>? _moodSub;

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

      // 3. Recent moods
      final recentMoods = await moodRepository.getMoodHistory(coupleId);

      // 4. Emit loaded
      emit(HomeLoaded(
        user:        user,
        partner:     partner,
        couple:      couple,
        recentMoods: recentMoods,
      ));

      // 5. Subscribe to live presence + mood streams
      _presenceSub?.cancel();
      _moodSub?.cancel();

      _presenceSub = coupleRepository
          .watchPartnerPresence(coupleId, partnerId)
          .listen((isOnline) { if (!isClosed) add(PartnerPresenceUpdated(isOnline)); });

      _moodSub = moodRepository
          .watchPartnerMood(coupleId, partnerId)
          .listen((mood) { if (!isClosed) add(PartnerMoodUpdated(mood)); });

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

  void _onMood(PartnerMoodUpdated e, Emitter<HomeState> emit) {
    if (state is HomeLoaded) {
      emit((state as HomeLoaded).copyWith(partnerMood: e.mood));
    }
  }

  void _onMoodsRefreshed(RecentMoodsRefreshed e, Emitter<HomeState> emit) {
    if (state is HomeLoaded) {
      emit((state as HomeLoaded).copyWith(recentMoods: e.moods));
    }
  }

  @override
  Future<void> close() {
    _presenceSub?.cancel();
    _moodSub?.cancel();
    return super.close();
  }
}
