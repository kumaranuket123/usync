part of 'onboarding_bloc.dart';

sealed class OnboardingEvent { const OnboardingEvent(); }
final class PageAdvanced       extends OnboardingEvent {}
final class PageChanged        extends OnboardingEvent { PageChanged(this.index); final int index; }
final class OnboardingSkipped  extends OnboardingEvent {}
final class OnboardingCompleted extends OnboardingEvent {}
