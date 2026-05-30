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

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id:          json['id']          as String,
    username:    json['username']    as String,
    email:       json['email']       as String,
    avatarEmoji: json['avatarEmoji'] as String,
    createdAt:   DateTime.parse(json['createdAt'] as String),
    coupleId:    json['coupleId']    as String?,
    fcmToken:    json['fcmToken']    as String?,
  );

  Map<String, dynamic> toJson() => {
    'id':          id,
    'username':    username,
    'email':       email,
    'avatarEmoji': avatarEmoji,
    'createdAt':   createdAt.toIso8601String(),
    'coupleId':    coupleId,
    'fcmToken':    fcmToken,
  };

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
