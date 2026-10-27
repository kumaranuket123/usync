part of 'splash_bloc.dart';

enum SplashDestination { onboarding, login, pairInvite, home, updateRequired }

sealed class SplashState {}
final class SplashLoading    extends SplashState {}
final class SplashNavigating extends SplashState {
  SplashNavigating(this.destination);
  final SplashDestination destination;
}
