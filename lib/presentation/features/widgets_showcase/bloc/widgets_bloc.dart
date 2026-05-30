import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/couple.dart';
import '../../../../domain/entities/mood.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_mood_repository.dart';

part 'widgets_event.dart';
part 'widgets_state.dart';

class WidgetsBloc extends Bloc<WidgetsBlocEvent, WidgetsBlocState> {
  WidgetsBloc({required this.moodRepository, required this.coupleRepository})
      : super(WidgetsLoading()) {
    on<WidgetsLoaded>(_onLoaded);
  }

  final IMoodRepository   moodRepository;
  final ICoupleRepository coupleRepository;

  Future<void> _onLoaded(WidgetsLoaded e, Emitter<WidgetsBlocState> emit) async {
    if (e.coupleId.isEmpty) return;
    emit(WidgetsLoading());
    try {
      final couple = await coupleRepository.getCouple(e.coupleId);
      emit(WidgetsReady(couple: couple));
    } catch (_) {}
  }
}
