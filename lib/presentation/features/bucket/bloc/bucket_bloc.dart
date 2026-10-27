import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/bucket_item.dart';
import '../../../../domain/repositories/i_bucket_repository.dart';

part 'bucket_event.dart';
part 'bucket_state.dart';

class BucketBloc extends Bloc<BucketEvent, BucketState> {
  BucketBloc({required this.bucketRepository, this.loadTimeout = const Duration(seconds: 5)})
      : super(const BucketLoading()) {
    on<BucketOpened>(_onOpened);
    on<_ItemsChanged>(_onItemsChanged);
    on<_LoadTimedOut>(_onLoadTimedOut);
    on<ItemAdded>(_onAdded);
    on<ItemToggled>(_onToggled);
    on<ItemRemoved>(_onRemoved);
  }

  final IBucketRepository bucketRepository;
  /// How long to wait for the first list before showing an empty one (offline, nothing saved).
  final Duration loadTimeout;

  String _coupleId = '', _userId = '';
  List<BucketItem> _items = const [];
  /// Adds waiting to be sent, shown meanwhile; dropped once the server list has them.
  final _pending = <String, BucketItem>{};
  StreamSubscription<List<BucketItem>>? _sub;
  Timer? _timer;

  Future<void> _onOpened(BucketOpened e, Emitter<BucketState> emit) async {
    _coupleId = e.coupleId;
    _userId   = e.userId;
    emit(const BucketLoading());
    await _sub?.cancel();
    _sub = bucketRepository.watchItems(_coupleId).listen(
      (items) { if (!isClosed) add(_ItemsChanged(items)); },
      onError: (_) {},
    );
    _timer?.cancel();
    _timer = Timer(loadTimeout, () { if (!isClosed) add(_LoadTimedOut()); });
  }

  void _onItemsChanged(_ItemsChanged e, Emitter<BucketState> emit) {
    _timer?.cancel();
    _items = e.items;
    _pending.removeWhere((id, _) => _items.any((i) => i.id == id));
    emit(_ready());
  }

  void _onLoadTimedOut(_LoadTimedOut _, Emitter<BucketState> emit) {
    if (state is BucketLoading) emit(_ready());
  }

  BucketReady _ready({String? notice}) {
    final all   = [..._pending.values, ..._items];
    final todo  = all.where((i) => !i.isDone).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final done  = all.where((i) => i.isDone).toList()..sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
    return BucketReady(items: [...todo, ...done], pendingIds: _pending.keys.toSet(), notice: notice);
  }

  Future<void> _onAdded(ItemAdded e, Emitter<BucketState> emit) async {
    final title = e.title.trim();
    if (title.isEmpty || state is! BucketReady) return;
    final note = e.note?.trim();
    try {
      final result = await bucketRepository.addItem(
        coupleId: _coupleId,
        userId:   _userId,
        title:    title,
        emoji:    e.emoji,
        note:     note == null || note.isEmpty ? null : note,
      );
      if (result.sentNow) return; // the live list brings it back
      _pending[result.item.id] = result.item;
      emit(_ready(notice: 'You are offline. It will be added when you are back online.'));
    } catch (_) {
      emit(_ready(notice: 'Could not add it. Try again.'));
    }
  }

  Future<void> _onToggled(ItemToggled e, Emitter<BucketState> emit) async {
    if (_pending.containsKey(e.item.id)) return; // not on the server yet
    try {
      await bucketRepository.setDone(
        coupleId: _coupleId,
        userId:   _userId,
        item:     e.item,
        done:     !e.item.isDone,
      );
    } catch (_) {
      emit(_ready(notice: 'Could not update it. Check your connection.'));
    }
  }

  Future<void> _onRemoved(ItemRemoved e, Emitter<BucketState> emit) async {
    if (_pending.remove(e.id) != null) {
      emit(_ready());
      return;
    }
    try {
      await bucketRepository.deleteItem(e.id);
      // Realtime does not reliably deliver filtered delete events, so drop it here too.
      _items = _items.where((i) => i.id != e.id).toList();
      emit(_ready());
    } catch (_) {
      emit(_ready(notice: 'Could not delete it. Check your connection.'));
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    _timer?.cancel();
    return super.close();
  }
}
