part of 'bucket_bloc.dart';

sealed class BucketEvent { const BucketEvent(); }
final class BucketOpened extends BucketEvent {
  BucketOpened({required this.coupleId, required this.userId});
  final String coupleId, userId;
}
final class _ItemsChanged extends BucketEvent {
  _ItemsChanged(this.items);
  final List<BucketItem> items;
}
final class _LoadTimedOut extends BucketEvent {}
final class ItemAdded extends BucketEvent {
  ItemAdded({required this.title, required this.emoji, this.note});
  final String  title, emoji;
  final String? note;
}
final class ItemToggled extends BucketEvent {
  ItemToggled(this.item);
  final BucketItem item;
}
final class ItemRemoved extends BucketEvent {
  ItemRemoved(this.id);
  final String id;
}
