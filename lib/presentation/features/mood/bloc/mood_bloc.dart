import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/mood.dart';
import '../../../../domain/repositories/i_mood_repository.dart';

part 'mood_event.dart';
part 'mood_state.dart';

class MoodBloc extends Bloc<MoodEvent, MoodState> {
  MoodBloc({required this.moodRepository}) : super(MoodReady()) {
    on<MoodScreenOpened>(_onOpened);
    on<MoodSelected>((e, emit) {
      if (state is MoodReady) emit((state as MoodReady).copyWith(selectedMood: e.type));
    });
    on<MoodSent>(_onSent);
  }

  final IMoodRepository moodRepository;
  String _coupleId = '';
  String _userId   = '';

  Future<void> _onOpened(MoodScreenOpened e, Emitter<MoodState> emit) async {
    _coupleId = e.coupleId;
    _userId   = e.userId;
    emit(MoodLoading());
    final last = await moodRepository.getLastSentMood(_userId);
    emit(MoodReady(selectedMood: last?.type));
  }

  Future<void> _onSent(MoodSent _, Emitter<MoodState> emit) async {
    final ready = state as MoodReady?;
    if (ready?.selectedMood == null) {
      emit(MoodError('Pick a mood first'));
      return;
    }
    emit(ready!.copyWith(isSending: true));
    try {
      await moodRepository.sendMood(_coupleId, _userId, ready.selectedMood!);
      emit(MoodSentSuccess());
    } catch (err) {
      emit(MoodError(err.toString()));
    }
  }
}
