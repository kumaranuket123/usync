part of 'profile_bloc.dart';
sealed class ProfileState {}
final class ProfileLoading extends ProfileState {}
final class ProfileReady   extends ProfileState {
  ProfileReady({required this.user, required this.couple});
  final AppUser user;
  final Couple  couple;
}
final class ProfileError   extends ProfileState { ProfileError(this.message); final String message; }
final class ProfileDisconnected   extends ProfileState {}
