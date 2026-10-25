import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/models/milestone_model.dart';
import '../../../../domain/entities/milestone.dart';
import '../../../../domain/entities/notification_item.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_notification_repository.dart';

part 'timeline_event.dart';
part 'timeline_state.dart';

class TimelineBloc extends Bloc<TimelineEvent, TimelineState> {
  TimelineBloc({required this.coupleRepository, required this.client, required this.notifications})
      : super(TimelineLoading()) {
    on<TimelineLoaded>(_onLoaded);
    on<DateAdded>(_onAdded);
    on<DateDeleted>(_onDeleted);
  }

  final ICoupleRepository       coupleRepository;
  final SupabaseClient          client;
  final INotificationRepository notifications;

  String _coupleId = '';

  Future<void> _onLoaded(TimelineLoaded e, Emitter<TimelineState> emit) async {
    _coupleId = e.coupleId;
    if (e.coupleId.isEmpty) { emit(TimelineEmpty(0)); return; }
    emit(TimelineLoading());
    await _load(emit);
  }

  /// Loads the timeline; [notice] is shown once by the screen if it is set.
  Future<void> _load(Emitter<TimelineState> emit, {String? notice}) async {
    try {
      final couple = await coupleRepository.getCouple(_coupleId);
      final days   = couple.daysTogether;

      final rows = await client
          .from('milestones')
          .select()
          .eq('couple_id', _coupleId)
          .order('occurred_at');
      // Typed as Milestone (not MilestoneModel) so the synthetic "today" item can be added.
      final milestones = <Milestone>[for (final row in rows) MilestoneModel.fromRow(row)];

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
    final uid = client.auth.currentUser?.id;
    if (uid == null || _coupleId.isEmpty) return;
    String? notice;
    try {
      // Noon UTC keeps the calendar day the same in every timezone.
      final occurredAt = DateTime.utc(e.date.year, e.date.month, e.date.day, 12);
      await client.from('milestones').insert({
        'couple_id':      _coupleId,
        'type':           MilestoneType.custom.name,
        'title':          e.title,
        'note':           e.note,
        'emoji':          e.emoji,
        'repeats_yearly': e.repeatsYearly,
        'occurred_at':    occurredAt.toIso8601String(),
        'created_by':     uid,
      });
      await notifications.notifyPartner(
        coupleId:   _coupleId,
        fromUserId: uid,
        type:       NotifType.milestone,
        body:       (name) => '$name added "${e.title}" to your timeline ${e.emoji}',
      );
    } catch (_) {
      notice = 'Could not save this date';
    }
    await _load(emit, notice: notice);
  }

  Future<void> _onDeleted(DateDeleted e, Emitter<TimelineState> emit) async {
    String? notice;
    try {
      await client.from('milestones').delete().eq('id', e.id);
    } catch (_) {
      notice = 'Could not delete this date';
    }
    await _load(emit, notice: notice);
  }
}
