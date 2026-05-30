import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/memory.dart';
import '../../../../domain/repositories/i_memory_repository.dart';

part 'memory_event.dart';
part 'memory_state.dart';

class MemoryBloc extends Bloc<MemoryEvent, MemoryState> {
  MemoryBloc({required this.memoryRepository}) : super(MemoryLoading()) {
    on<MemoriesLoaded>(_onLoaded);
    on<MemoriesUpdated>(_onUpdated);
    on<MemoryFavourited>(_onFavourite);
    on<MemoryDeleted>(_onDelete);
  }

  final IMemoryRepository memoryRepository;
  StreamSubscription<List<Memory>>? _sub;

  Future<void> _onLoaded(MemoriesLoaded e, Emitter<MemoryState> emit) async {
    if (e.coupleId.isEmpty) { emit(MemoryEmpty()); return; }
    emit(MemoryLoading());
    _sub = memoryRepository
        .watchMemories(e.coupleId)
        .listen((m) { if (!isClosed) add(MemoriesUpdated(m)); });
  }

  void _onUpdated(MemoriesUpdated e, Emitter<MemoryState> emit) {
    if (e.memories.isEmpty) {
      emit(MemoryEmpty());
    } else {
      emit(MemoryLoaded(e.memories));
    }
  }

  Future<void> _onFavourite(MemoryFavourited e, Emitter<MemoryState> emit) async {
    if (state is! MemoryLoaded) return;
    final list = (state as MemoryLoaded).memories;
    final updated = list.map((m) => m.id == e.id ? m.copyWith(isFavourited: e.isFavourited) : m).toList();
    emit(MemoryLoaded(updated));
    await memoryRepository.toggleFavourite(e.id, e.coupleId, isFavourited: e.isFavourited);
  }

  Future<void> _onDelete(MemoryDeleted e, Emitter<MemoryState> emit) async {
    if (state is! MemoryLoaded) return;
    final updated = (state as MemoryLoaded).memories.where((m) => m.id != e.id).toList();
    emit(updated.isEmpty ? MemoryEmpty() : MemoryLoaded(updated));
    await memoryRepository.deleteMemory(e.id, e.coupleId);
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
