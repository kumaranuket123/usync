part of 'memory_bloc.dart';
sealed class MemoryEvent { const MemoryEvent(); }
final class MemoriesLoaded    extends MemoryEvent { MemoriesLoaded(this.coupleId); final String coupleId; }
final class MemoriesUpdated   extends MemoryEvent { MemoriesUpdated(this.memories); final List<Memory> memories; }
final class MemoryFavourited  extends MemoryEvent { MemoryFavourited({required this.id, required this.coupleId, required this.isFavourited}); final String id, coupleId; final bool isFavourited; }
final class MemoryDeleted     extends MemoryEvent { MemoryDeleted({required this.id, required this.coupleId}); final String id, coupleId; }
