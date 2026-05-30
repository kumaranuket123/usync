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

  /// "May 28, 2026"
  String get formatted {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${months[month - 1]} $day, $year';
  }

  /// "Together since Jan 12, 2026"
  String get togetheSince => 'Together since $formatted';

  int get daysSinceNow => DateTime.now().difference(this).inDays;
}
