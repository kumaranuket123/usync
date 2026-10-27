part of 'bucket_bloc.dart';

sealed class BucketState { const BucketState(); }
final class BucketLoading extends BucketState {
  const BucketLoading();
}
final class BucketReady extends BucketState {
  const BucketReady({this.items = const [], this.pendingIds = const {}, this.notice});

  /// To-do items first (newest first), then done ones (most recently done first).
  final List<BucketItem> items;
  /// Items saved on this phone and not sent yet (no connection).
  final Set<String>      pendingIds;
  /// Shown once by the screen.
  final String?          notice;

  int get doneCount => items.where((i) => i.isDone).length;
}
