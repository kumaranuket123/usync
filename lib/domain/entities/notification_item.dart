import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum NotifType {
  touch,
  doodle,
  moodChange,
  streak,
  milestone,
  location,
  locate,
  question;

  String get emoji => switch (this) {
    NotifType.touch      => '👆',
    NotifType.doodle     => '✏️',
    NotifType.moodChange => '💭',
    NotifType.streak     => '🔥',
    NotifType.milestone  => '💖',
    NotifType.location   => '📍',
    NotifType.locate     => '📍',
    NotifType.question   => '💬',
  };

  Color get iconBackground => switch (this) {
    NotifType.touch      => const Color(0x1FFF2D78),
    NotifType.doodle     => const Color(0x1F00D4FF),
    NotifType.moodChange => const Color(0x1F9D4EDD),
    NotifType.streak     => const Color(0x1AFFD700),
    NotifType.milestone  => const Color(0x1FC77DFF),
    NotifType.location   => const Color(0x1F00E676),
    NotifType.locate     => const Color(0x1F00E676),
    NotifType.question   => const Color(0x1F00D4FF),
  };

  /// Settings group: 'locate' (a requested fix) is controlled together with 'location'.
  String get soundGroup => this == NotifType.locate ? NotifType.location.name : name;

  /// Groups that start out silent for a new user.
  static const Set<String> defaultSilent = {'location'};

  static NotifType fromString(String value) =>
      NotifType.values.firstWhere((e) => e.name == value, orElse: () => NotifType.milestone);
}

class NotificationItem extends Equatable {
  const NotificationItem({
    required this.id,
    required this.coupleId,
    required this.type,
    required this.bodyText,
    required this.timestamp,
    this.isRead = false,
    this.fromUserId,
  });

  final String    id;
  final String    coupleId;
  final NotifType type;
  final String    bodyText;
  final DateTime  timestamp;
  final bool      isRead;
  /// Sender; the recipient is their partner. Drives the push in `functions/`.
  final String?   fromUserId;

  NotificationItem markRead() => NotificationItem(
    id:        id,
    coupleId:  coupleId,
    type:      type,
    bodyText:  bodyText,
    timestamp: timestamp,
    isRead:    true,
    fromUserId: fromUserId,
  );

  @override
  List<Object?> get props => [id, isRead];
}
