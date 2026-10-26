import 'package:equatable/equatable.dart';

/// A user's position at a moment in time. Only ever travels over the couple's
/// Realtime channel; it is never persisted.
class SharedLocation extends Equatable {
  const SharedLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    this.allowsBackground = false,
  });

  final double   latitude;
  final double   longitude;
  /// Horizontal accuracy in metres.
  final double   accuracy;
  final DateTime timestamp;
  /// The owner lets their partner request a fresh fix while the app is closed.
  final bool     allowsBackground;

  @override
  List<Object?> get props => [latitude, longitude, accuracy, timestamp, allowsBackground];
}
