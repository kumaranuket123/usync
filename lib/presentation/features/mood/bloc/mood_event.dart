part of 'mood_bloc.dart';
sealed class MoodEvent { const MoodEvent(); }
final class MoodScreenOpened extends MoodEvent { MoodScreenOpened({required this.coupleId, required this.userId}); final String coupleId, userId; }
final class MoodSelected     extends MoodEvent { MoodSelected(this.type); final MoodType type; }
final class MoodSent         extends MoodEvent {}
