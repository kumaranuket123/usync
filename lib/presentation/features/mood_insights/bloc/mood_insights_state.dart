part of 'mood_insights_bloc.dart';

sealed class MoodInsightsState { const MoodInsightsState(); }
final class InsightsLoading extends MoodInsightsState {
  const InsightsLoading();
}
final class InsightsReady extends MoodInsightsState {
  const InsightsReady({required this.insights, required this.partnerName});
  final MoodInsights insights;
  final String       partnerName;
}
final class InsightsError extends MoodInsightsState {
  const InsightsError(this.message);
  final String message;
}
