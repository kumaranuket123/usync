part of 'memory_bloc.dart';
sealed class MemoryState {}
final class MemoryLoading extends MemoryState {}
final class MemoryLoaded  extends MemoryState { MemoryLoaded(this.memories); final List<Memory> memories; }
final class MemoryEmpty   extends MemoryState {}
final class MemoryError   extends MemoryState { MemoryError(this.message); final String message; }
