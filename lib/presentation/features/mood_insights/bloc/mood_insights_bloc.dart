import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/mood_insights.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_mood_repository.dart';

part 'mood_insights_event.dart';
part 'mood_insights_state.dart';

class MoodInsightsBloc extends Bloc<MoodInsightsEvent, MoodInsightsState> {
  MoodInsightsBloc({
    required this.moodRepository,
    required this.coupleRepository,
    required this.authRepository,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        super(const InsightsLoading()) {
    on<InsightsOpened>(_onOpened);
  }

  final IMoodRepository   moodRepository;
  final ICoupleRepository coupleRepository;
  final IAuthRepository   authRepository;
  final DateTime Function() _clock;

  /// How many days (today included) the insights cover.
  static const windowDays = 7;

  Future<void> _onOpened(InsightsOpened e, Emitter<MoodInsightsState> emit) async {
    emit(const InsightsLoading());
    final now   = _clock();
    final today = DateTime.utc(now.toUtc().year, now.toUtc().month, now.toUtc().day);
    final since = today.subtract(const Duration(days: windowDays - 1));
    try {
      final moods = await moodRepository.getMoodsSince(e.coupleId, since);
      emit(InsightsReady(
        insights:    MoodInsights.compute(moods, userId: e.userId, now: now, days: windowDays),
        partnerName: await _partnerName(e.coupleId, e.userId),
      ));
    } catch (_) {
      emit(const InsightsError('Could not load your insights. Check your connection.'));
    }
  }

  Future<String> _partnerName(String coupleId, String userId) async {
    try {
      final couple  = await coupleRepository.getCouple(coupleId);
      final partner = await authRepository.getUserById(couple.partnerIdFor(userId));
      final name    = partner?.username.trim() ?? '';
      return name.isEmpty ? 'Your partner' : name;
    } catch (_) {
      return 'Your partner';
    }
  }
}
