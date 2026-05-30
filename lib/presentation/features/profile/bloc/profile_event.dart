part of 'profile_bloc.dart';
sealed class ProfileEvent { const ProfileEvent(); }
final class ProfileLoaded  extends ProfileEvent { ProfileLoaded({required this.userId, required this.coupleId}); final String userId, coupleId; }
final class AvatarChanged  extends ProfileEvent { AvatarChanged({required this.userId, required this.emoji}); final String userId, emoji; }
