import '../../domain/entities/user.dart';

class UserModel extends AppUser {
  const UserModel({
    required super.id,
    required super.username,
    required super.email,
    required super.avatarEmoji,
    required super.createdAt,
    super.coupleId,
    super.fcmToken,
  });

  /// Row from the Supabase `profiles` table.
  factory UserModel.fromProfile(Map<String, dynamic> row) => UserModel(
    id:          row['id']           as String,
    username:    row['username']     as String,
    email:       row['email']        as String,
    avatarEmoji: row['avatar_emoji'] as String,
    createdAt:   DateTime.parse(row['created_at'] as String),
    coupleId:    row['couple_id']    as String?,
  );

  factory UserModel.fromEntity(AppUser user) => UserModel(
    id:          user.id,
    username:    user.username,
    email:       user.email,
    avatarEmoji: user.avatarEmoji,
    createdAt:   user.createdAt,
    coupleId:    user.coupleId,
    fcmToken:    user.fcmToken,
  );
}
