part of 'mood_bloc.dart';
sealed class MoodState {}
final class MoodLoading     extends MoodState {}
final class MoodReady       extends MoodState {
  MoodReady({this.selectedMood, this.isSending = false});
  final MoodType? selectedMood;
  final bool      isSending;
  MoodReady copyWith({MoodType? selectedMood, bool? isSending}) =>
      MoodReady(selectedMood: selectedMood ?? this.selectedMood, isSending: isSending ?? this.isSending);
}
final class MoodSentSuccess extends MoodState {}
final class MoodError       extends MoodState { MoodError(this.message); final String message; }
