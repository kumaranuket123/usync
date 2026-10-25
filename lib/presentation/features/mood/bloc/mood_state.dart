part of 'mood_bloc.dart';
sealed class MoodState {}
final class MoodLoading     extends MoodState {}
final class MoodReady       extends MoodState {
  MoodReady({this.selectedMood, this.selectedCustom, this.customMoods = const [], this.isSending = false});
  final MoodType?         selectedMood;
  /// Set when [selectedMood] is [MoodType.custom].
  final CustomMood?       selectedCustom;
  /// The user's own moods from before, offered next to the built-in ones.
  final List<CustomMood>  customMoods;
  final bool              isSending;

  MoodReady copyWith({
    MoodType?         selectedMood,
    CustomMood?       selectedCustom,
    bool              clearCustom = false,
    List<CustomMood>? customMoods,
    bool?             isSending,
  }) =>
      MoodReady(
        selectedMood:   selectedMood   ?? this.selectedMood,
        selectedCustom: clearCustom ? null : (selectedCustom ?? this.selectedCustom),
        customMoods:    customMoods    ?? this.customMoods,
        isSending:      isSending      ?? this.isSending,
      );
}
final class MoodSentSuccess extends MoodState {
  MoodSentSuccess({this.queued = false});
  /// There was no connection: the mood is saved on the device and goes out later.
  final bool queued;
}
final class MoodError       extends MoodState { MoodError(this.message); final String message; }
