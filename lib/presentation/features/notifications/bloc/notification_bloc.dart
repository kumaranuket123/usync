import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/notification_item.dart';
import '../../../../domain/repositories/i_notification_repository.dart';

part 'notification_event.dart';
part 'notification_state.dart';

class NotificationBloc extends Bloc<NotificationEvent, NotifState> {
  NotificationBloc({required this.notificationRepository}) : super(NotifLoading()) {
    on<NotificationsLoaded>(_onLoaded);
    on<NotificationsUpdated>((e, emit) => emit(NotifReady(e.items)));
    on<NotificationRead>(_onRead);
    on<AllNotificationsRead>(_onAllRead);
  }

  final INotificationRepository notificationRepository;
  StreamSubscription<List<NotificationItem>>? _sub;

  Future<void> _onLoaded(NotificationsLoaded e, Emitter<NotifState> emit) async {
    if (e.coupleId.isEmpty) { emit(NotifReady([])); return; }
    emit(NotifLoading());
    _sub = notificationRepository
        .watchNotifications(e.coupleId)
        .listen((items) { if (!isClosed) add(NotificationsUpdated(items)); });
  }

  Future<void> _onRead(NotificationRead e, Emitter<NotifState> emit) async {
    if (state is! NotifReady) return;
    final updated = (state as NotifReady).items.map((n) => n.id == e.id ? n.markRead() : n).toList();
    emit(NotifReady(updated));
    await notificationRepository.markRead(e.coupleId, e.id);
  }

  Future<void> _onAllRead(AllNotificationsRead e, Emitter<NotifState> emit) async {
    if (state is! NotifReady) return;
    final updated = (state as NotifReady).items.map((n) => n.markRead()).toList();
    emit(NotifReady(updated));
    await notificationRepository.markAllRead(e.coupleId);
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
