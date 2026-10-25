import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/milestone_model.dart';
import '../../../../domain/entities/milestone.dart';
import '../../../../domain/repositories/i_couple_repository.dart';

part 'timeline_event.dart';
part 'timeline_state.dart';

class TimelineBloc extends Bloc<TimelineEvent, TimelineState> {
  TimelineBloc({required this.coupleRepository, required this.client})
      : super(TimelineLoading()) {
    on<TimelineLoaded>(_onLoaded);
  }

  final ICoupleRepository coupleRepository;
  final SupabaseClient    client;

  Future<void> _onLoaded(TimelineLoaded e, Emitter<TimelineState> emit) async {
    if (e.coupleId.isEmpty) { emit(TimelineEmpty(0)); return; }
    emit(TimelineLoading());
    try {
      final couple = await coupleRepository.getCouple(e.coupleId);
      final days   = couple.daysTogether;

      final rows = await client
          .from('milestones')
          .select()
          .eq('couple_id', e.coupleId)
          .order('occurred_at');
      final List<Milestone> milestones = rows.map(MilestoneModel.fromRow).toList();

      // Append synthetic "today" item.
      milestones.add(Milestone(
        id:         'today',
        coupleId:   e.coupleId,
        type:       MilestoneType.today,
        title:      'Today · Day $days',
        note:       'Still here. Still close. Still together.',
        occurredAt: DateTime.now(),
      ));

      emit(milestones.length == 1
          ? TimelineEmpty(days)
          : TimelineReady(milestones: milestones, daysTogether: days));
    } catch (err) {
      emit(TimelineError(err.toString()));
    }
  }
}
