part of 'profile_bloc.dart';
sealed class ProfileEvent { const ProfileEvent(); }
final class ProfileLoaded  extends ProfileEvent { ProfileLoaded({required this.userId, required this.coupleId}); final String userId, coupleId; }
final class DisconnectCouple extends ProfileEvent { DisconnectCouple({required this.userId, required this.coupleId}); final String userId, coupleId; }
/// The signed-in user's own details changed (e.g. a new name).
final class UserUpdated         extends ProfileEvent { UserUpdated(this.user); final AppUser user; }
final class CoupleUpdated       extends ProfileEvent { CoupleUpdated(this.couple); final Couple couple; }
final class AvatarChanged  extends ProfileEvent { AvatarChanged({required this.userId, required this.emoji}); final String userId, emoji; }
