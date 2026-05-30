import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/couple.dart';
import '../../../../domain/repositories/i_couple_repository.dart';

part 'pairing_event.dart';
part 'pairing_state.dart';

class PairingBloc extends Bloc<PairingEvent, PairingState> {
  PairingBloc({required this.coupleRepository}) : super(PairingInitial()) {
    on<GenerateCodeRequested>(_onGenerate);
    on<JoinWithCodeRequested>(_onJoin);
    on<PairingReset>((_, emit) => emit(PairingInitial()));
  }

  final ICoupleRepository coupleRepository;

  Future<void> _onGenerate(GenerateCodeRequested e, Emitter<PairingState> emit) async {
    emit(PairingLoading());
    try {
      final code = await coupleRepository.generateInviteCode(e.userId);
      emit(CodeGenerated(code));
    } catch (err) {
      emit(PairingError(err.toString()));
    }
  }

  Future<void> _onJoin(JoinWithCodeRequested e, Emitter<PairingState> emit) async {
    emit(PairingLoading());
    try {
      final couple = await coupleRepository.joinWithCode(e.code, e.userId);
      emit(PairingSuccess(couple));
    } catch (err) {
      emit(PairingError(err.toString()));
    }
  }
}
