import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/entities/milestone.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_milestone_repository.dart';

part 'timeline_event.dart';
part 'timeline_state.dart';

class TimelineBloc extends Bloc<TimelineEvent, TimelineState> {
  TimelineBloc({required this.coupleRepository, required this.milestoneRepository})
      : super(TimelineLoading()) {
    on<TimelineLoaded>(_onLoaded);
    on<DateAdded>(_onAdded);
    on<DateDeleted>(_onDeleted);
  }

  final ICoupleRepository    coupleRepository;
  final IMilestoneRepository milestoneRepository;

  String _coupleId = '';
  final _auth = Supabase.instance.client.auth;

  Future<void> _onLoaded(TimelineLoaded e, Emitter<TimelineState> emit) async {
    _coupleId = e.coupleId;
    if (e.coupleId.isEmpty) { emit(TimelineEmpty(0)); return; }
    emit(TimelineLoading());
    await _load(emit);
  }

  /// Loads the timeline; [notice] is shown once by the screen if it is set.
  /// [pending] are dates saved on the device but not yet sent, shown meanwhile.
  Future<void> _load(Emitter<TimelineState> emit, {String? notice, List<Milestone> pending = const []}) async {
    try {
      final couple = await coupleRepository.getCouple(_coupleId);
      final days   = couple.daysTogether;

      final milestones = await milestoneRepository.getMilestones(_coupleId);
      milestones.addAll(pending.where((p) => !milestones.any((m) => m.id == p.id)));

      // Insert the synthetic "today" item in date order: later dates are upcoming.
      milestones.add(Milestone(
        id:         'today',
        coupleId:   _coupleId,
        type:       MilestoneType.today,
        title:      'Today · Day $days',
        note:       'Still here. Still close. Still together.',
        occurredAt: DateTime.now(),
      ));

      milestones.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

      emit(TimelineReady(milestones: milestones, daysTogether: days, notice: notice));
    } catch (err) {
      debugPrint('Timeline load failed: $err');
      emit(TimelineError(err.toString()));
    }
  }

  Future<void> _onAdded(DateAdded e, Emitter<TimelineState> emit) async {
    final uid = _auth.currentUser?.id;
    if (uid == null || _coupleId.isEmpty) return;
    try {
      final result = await milestoneRepository.addDate(
        coupleId:      _coupleId,
        userId:        uid,
        title:         e.title,
        date:          e.date,
        note:          e.note,
        emoji:         e.emoji,
        repeatsYearly: e.repeatsYearly,
      );
      await _load(
        emit,
        pending: result.sentNow ? const [] : [result.milestone],
        notice:  result.sentNow ? null : 'Saved on this device. It will be sent when you are back online.',
      );
    } catch (_) {
      await _load(emit, notice: 'Could not save this date');
    }
  }

  Future<void> _onDeleted(DateDeleted e, Emitter<TimelineState> emit) async {
    String? notice;
    try {
      await milestoneRepository.deleteMilestone(e.id);
    } catch (_) {
      notice = 'Could not delete this date. Check your connection.';
    }
    await _load(emit, notice: notice);
  }
}
