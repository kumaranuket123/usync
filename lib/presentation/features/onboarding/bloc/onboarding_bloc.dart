import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/datasources/local/prefs_source.dart';

part 'onboarding_event.dart';
part 'onboarding_state.dart';

class OnboardingBloc extends Bloc<OnboardingEvent, OnboardingState> {
  OnboardingBloc({required this.prefsSource}) : super(const OnboardingState()) {
    on<PageAdvanced>(_onAdvanced);
    on<PageChanged>(_onPageChanged);
    on<OnboardingSkipped>(_onDone);
    on<OnboardingCompleted>(_onDone);
  }

  final PrefsSource prefsSource;

  void _onAdvanced(PageAdvanced _, Emitter<OnboardingState> emit) {
    if (!state.isLastPage) {
      emit(OnboardingState(currentPage: state.currentPage + 1));
    } else {
      add(OnboardingCompleted());
    }
  }

  void _onPageChanged(PageChanged event, Emitter<OnboardingState> emit) {
    emit(OnboardingState(currentPage: event.index));
  }

  Future<void> _onDone(OnboardingEvent _, Emitter<OnboardingState> emit) async {
    await prefsSource.setOnboardingSeen();
    emit(const OnboardingState(done: true));
  }
}
