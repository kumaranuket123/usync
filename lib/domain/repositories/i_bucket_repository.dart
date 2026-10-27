import '../entities/bucket_item.dart';

abstract interface class IBucketRepository {
  /// The couple's items (both partners), newest first. Emits the copy saved on
  /// the device straight away, then live updates, so a partner's change shows up
  /// without reopening the screen.
  Stream<List<BucketItem>> watchItems(String coupleId);

  /// Adds an item and tells the partner. [sentNow] is false when there was no
  /// connection: it is saved on the device and sent later, and [item] is what to
  /// show meanwhile.
  Future<({bool sentNow, BucketItem item})> addItem({
    required String coupleId,
    required String userId,
    required String title,
    required String emoji,
    String?         note,
  });

  /// Ticks an item off (or back on) and, when ticked, tells the partner.
  /// Needs a connection.
  Future<void> setDone({
    required String     coupleId,
    required String     userId,
    required BucketItem item,
    required bool       done,
  });

  Future<void> deleteItem(String id);
}
