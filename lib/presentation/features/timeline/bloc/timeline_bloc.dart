import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/datasources/remote/firestore_source.dart';
import '../../../../data/models/milestone_model.dart';
import '../../../../domain/entities/milestone.dart';
import '../../../../domain/repositories/i_couple_repository.dart';

part 'timeline_event.dart';
part 'timeline_state.dart';

class TimelineBloc extends Bloc<TimelineEvent, TimelineState> {
  TimelineBloc({required this.coupleRepository, this.firestoreSource})
      : super(TimelineLoading()) {
    on<TimelineLoaded>(_onLoaded);
  }

  final ICoupleRepository coupleRepository;
  final FirestoreSource?  firestoreSource;

  Future<void> _onLoaded(TimelineLoaded e, Emitter<TimelineState> emit) async {
    if (e.coupleId.isEmpty) { emit(TimelineEmpty(0)); return; }
    emit(TimelineLoading());
    try {
      final couple = await coupleRepository.getCouple(e.coupleId);
      final days   = couple.daysTogether;

      List<Milestone> milestones = [];
      if (firestoreSource != null) {
        final snap = await firestoreSource!
            .milestoneEvents(e.coupleId)
            .orderBy('occurredAt')
            .get();
        milestones = snap.docs
            .map((d) => MilestoneModel.fromJson(d.id, d.data()))
            .cast<Milestone>()
            .toList();
      }

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
