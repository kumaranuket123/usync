part of 'mood_insights_bloc.dart';

sealed class MoodInsightsEvent { const MoodInsightsEvent(); }
final class InsightsOpened extends MoodInsightsEvent {
  InsightsOpened({required this.coupleId, required this.userId});
  final String coupleId, userId;
}
