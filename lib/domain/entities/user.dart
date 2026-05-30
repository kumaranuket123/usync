import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.username,
    required this.email,
    required this.avatarEmoji,
    required this.createdAt,
    this.coupleId,
    this.fcmToken,
  });

  final String   id;
  final String   username;
  final String   email;
  final String   avatarEmoji;
  final DateTime createdAt;
  final String?  coupleId;
  final String?  fcmToken;

  bool get isPaired => coupleId != null;

  AppUser copyWith({
    String?   username,
    String?   avatarEmoji,
    String?   coupleId,
    String?   fcmToken,
  }) {
    return AppUser(
      id:          id,
      username:    username    ?? this.username,
      email:       email,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      createdAt:   createdAt,
      coupleId:    coupleId    ?? this.coupleId,
      fcmToken:    fcmToken    ?? this.fcmToken,
    );
  }

  @override
  List<Object?> get props => [id, username, email, avatarEmoji, coupleId];
}
