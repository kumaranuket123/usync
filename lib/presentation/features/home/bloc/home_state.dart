part of 'home_bloc.dart';

sealed class HomeState {}
final class HomeLoading extends HomeState {}
final class HomeLoaded  extends HomeState {
  HomeLoaded({
    required this.user,
    required this.partner,
    required this.couple,
    this.partnerMood,
    this.isOnline    = false,
    this.recentMoods = const [],
  });
  final AppUser    user;
  final AppUser    partner;
  final Couple     couple;
  final Mood?      partnerMood;
  final bool       isOnline;
  final List<Mood> recentMoods;

  HomeLoaded copyWith({bool? isOnline, Mood? partnerMood, List<Mood>? recentMoods}) =>
      HomeLoaded(
        user:        user,
        partner:     partner,
        couple:      couple,
        partnerMood: partnerMood  ?? this.partnerMood,
        isOnline:    isOnline     ?? this.isOnline,
        recentMoods: recentMoods  ?? this.recentMoods,
      );
}
final class HomeError extends HomeState { HomeError(this.message); final String message; }
