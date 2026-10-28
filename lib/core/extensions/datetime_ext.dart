extension DateTimeExt on DateTime {
  /// "2 hours ago", "Just now", "Yesterday", "May 28, 2026", etc.
  String get timeAgo {
    final diff = DateTime.now().difference(this);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)    return '${diff.inHours} hours ago';
    if (diff.inDays == 1)     return 'Yesterday';
    if (diff.inDays < 7)      return '${diff.inDays} days ago';
    return formatted;
  }

  /// "May 28, 2026", in the device's local time zone.
  String get formatted {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    final l = toLocal();
    return '${months[l.month - 1]} ${l.day}, ${l.year}';
  }

  /// "3:42 PM", in the device's local time zone.
  String get timeOfDay {
    final l = toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "May 28, 2026 · 3:42 PM", in the device's local time zone.
  String get formattedWithTime => '$formatted · $timeOfDay';

  /// "Together since Jan 12, 2026"
  String get togetheSince => 'Together since $formatted';

  int get daysSinceNow => DateTime.now().difference(this).inDays;
}
