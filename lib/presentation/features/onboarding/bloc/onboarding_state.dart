part of 'onboarding_bloc.dart';

class OnboardingState {
  const OnboardingState({this.currentPage = 0, this.done = false});
  final int  currentPage;
  final bool done;
  bool get isLastPage => currentPage == 3;
}
