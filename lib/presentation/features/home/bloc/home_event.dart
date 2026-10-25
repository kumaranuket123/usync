part of 'home_bloc.dart';

sealed class HomeEvent { const HomeEvent(); }
final class HomeStarted               extends HomeEvent {}
final class PartnerPresenceUpdated    extends HomeEvent { PartnerPresenceUpdated(this.isOnline); final bool isOnline; }
final class RecentMoodsRefreshed      extends HomeEvent { RecentMoodsRefreshed(this.moods); final List<Mood> moods; }
