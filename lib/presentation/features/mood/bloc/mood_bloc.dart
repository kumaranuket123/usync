import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/mood.dart';
import '../../../../domain/repositories/i_mood_repository.dart';

part 'mood_event.dart';
part 'mood_state.dart';

class MoodBloc extends Bloc<MoodEvent, MoodState> {
  MoodBloc({required this.moodRepository}) : super(MoodReady()) {
    on<MoodScreenOpened>(_onOpened);
    on<MoodSelected>((e, emit) {
      if (state is MoodReady) {
        emit((state as MoodReady).copyWith(selectedMood: e.type, clearCustom: true));
      }
    });
    on<CustomMoodSelected>((e, emit) {
      if (state is MoodReady) {
        emit((state as MoodReady).copyWith(selectedMood: MoodType.custom, selectedCustom: e.custom));
      }
    });
    on<CustomMoodAdded>((e, emit) {
      final current = state;
      if (current is! MoodReady) return;
      emit(current.copyWith(
        selectedMood:   MoodType.custom,
        selectedCustom: e.custom,
        customMoods:    [e.custom, ...current.customMoods.where((c) => c != e.custom)],
      ));
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
    Mood? last;
    try {
      last = await moodRepository.getLastSentMood(_userId);
    } catch (_) {
      // Offline: start with nothing selected.
    }
    var customs = <CustomMood>[];
    try {
      customs = await moodRepository.getMyCustomMoods(_userId);
    } catch (_) {
      // Custom moods unavailable (offline, or not set up yet): the built-in ones still work.
    }
    emit(MoodReady(
      selectedMood:   last?.type,
      selectedCustom: last?.type == MoodType.custom
          ? CustomMood(label: last!.label, emoji: last.emoji)
          : null,
      customMoods:    customs,
    ));
  }

  Future<void> _onSent(MoodSent _, Emitter<MoodState> emit) async {
    final ready = state as MoodReady?;
    if (ready?.selectedMood == null) {
      emit(MoodError('Pick a mood first'));
      return;
    }
    if (ready!.selectedMood == MoodType.custom && ready.selectedCustom == null) {
      emit(MoodError('Pick a mood first'));
      return;
    }
    emit(ready.copyWith(isSending: true));
    try {
      final sentNow = await moodRepository.sendMood(_coupleId, _userId, ready.selectedMood!, custom: ready.selectedCustom);
      emit(MoodSentSuccess(queued: !sentNow));
    } catch (err) {
      emit(MoodError(err.toString()));
    }
  }
}
