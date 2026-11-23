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
    this.unreadChat  = 0,
  });
  final AppUser    user;
  final AppUser    partner;
  final Couple     couple;
  final Mood?      partnerMood;
  final bool       isOnline;
  final List<Mood> recentMoods;
  /// Messages from the partner that this user has not seen yet (badge on the Chat button).
  final int        unreadChat;

  HomeLoaded copyWith({bool? isOnline, Mood? partnerMood, List<Mood>? recentMoods, int? unreadChat}) =>
      HomeLoaded(
        user:        user,
        partner:     partner,
        couple:      couple,
        partnerMood: partnerMood  ?? this.partnerMood,
        isOnline:    isOnline     ?? this.isOnline,
        recentMoods: recentMoods  ?? this.recentMoods,
        unreadChat:  unreadChat   ?? this.unreadChat,
      );
}
final class HomeError extends HomeState { HomeError(this.message); final String message; }
