part of 'onboarding_bloc.dart';

class OnboardingState {
  const OnboardingState({this.currentPage = 0, this.done = false});
  final int  currentPage;
  final bool done;
  /// The welcome has five slides (the last one is the privacy promise).
  static const lastPage = 4;
  bool get isLastPage => currentPage == lastPage;
}
