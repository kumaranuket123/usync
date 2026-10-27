import 'package:equatable/equatable.dart';

/// Where a couple stands with the (future) subscription. The server decides;
/// the app only shows it.
enum AccessStatus {
  /// The paywall is off: everyone has everything.
  free,
  /// An early member: free for good.
  grandfathered,
  premium,
  trial,
  expired;

  static AccessStatus fromString(String? value) =>
      AccessStatus.values.firstWhere((s) => s.name == value, orElse: () => AccessStatus.free);
}

class Access extends Equatable {
  const Access({this.status = AccessStatus.free, this.until, this.paywallEnabled = false});

  /// Full access, no paywall: what the app assumes when it cannot reach the server.
  const Access.open() : this();

  final AccessStatus status;
  /// When the trial or premium period ends (or ended); null when it does not apply.
  final DateTime?    until;
  final bool         paywallEnabled;

  /// Whole days left in the trial or premium period, counting today; 0 once it has passed.
  int daysLeft(DateTime now) {
    final end = until;
    if (end == null) return 0;
    final today = DateTime(now.year, now.month, now.day);
    final last  = DateTime(end.year, end.month, end.day);
    final days  = last.difference(today).inDays;
    return days < 0 ? 0 : days;
  }

  @override
  List<Object?> get props => [status, until, paywallEnabled];
}
