import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/couple.dart';
import '../../../../domain/entities/user.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_memory_repository.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  ProfileBloc({
    required this.authRepository,
    required this.coupleRepository,
    required this.memoryRepository,
  }) : super(ProfileLoading()) {
    on<ProfileLoaded>(_onLoaded);
  }

  final IAuthRepository   authRepository;
  final ICoupleRepository coupleRepository;
  final IMemoryRepository memoryRepository;

  Future<void> _onLoaded(ProfileLoaded e, Emitter<ProfileState> emit) async {
    if (e.coupleId.isEmpty || e.userId.isEmpty) { emit(ProfileError('Not paired')); return; }
    emit(ProfileLoading());
    try {
      final results = await Future.wait([
        authRepository.getCurrentUser(),
        coupleRepository.getCouple(e.coupleId),
        memoryRepository.getDoodleCount(e.coupleId),
      ]);
      emit(ProfileReady(
        user:         results[0] as AppUser,
        couple:       results[1] as Couple,
        doodleCount:  results[2] as int,
      ));
    } catch (err) {
      emit(ProfileError(err.toString()));
    }
  }
}
