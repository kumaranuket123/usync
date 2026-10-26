part of 'mood_bloc.dart';
sealed class MoodEvent { const MoodEvent(); }
final class MoodScreenOpened extends MoodEvent { MoodScreenOpened({required this.coupleId, required this.userId}); final String coupleId, userId; }
final class MoodSelected     extends MoodEvent { MoodSelected(this.type); final MoodType type; }
final class CustomMoodSelected extends MoodEvent { CustomMoodSelected(this.custom); final CustomMood custom; }
/// A brand new custom mood: added to the user's list and selected.
final class CustomMoodAdded    extends MoodEvent { CustomMoodAdded(this.custom); final CustomMood custom; }
final class MoodSent         extends MoodEvent {}
