import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/bucket_item.dart';
import 'package:usync/domain/repositories/i_bucket_repository.dart';
import 'package:usync/presentation/features/bucket/bloc/bucket_bloc.dart';

class _FakeBucketRepository implements IBucketRepository {
  final changes = StreamController<List<BucketItem>>.broadcast();
  bool sentNow = true;
  Object? error;
  final added = <String>[];
  final toggled = <(String, bool)>[];
  final deleted = <String>[];

  @override
  Stream<List<BucketItem>> watchItems(String coupleId) => changes.stream;

  @override
  Future<({bool sentNow, BucketItem item})> addItem({
    required String coupleId,
    required String userId,
    required String title,
    required String emoji,
    String? note,
  }) async {
    if (error != null) throw error!;
    added.add(title);
    return (
      sentNow: sentNow,
      item: BucketItem(id: 'new-${added.length}', coupleId: coupleId, title: title, emoji: emoji, note: note, createdAt: DateTime(2026, 5)),
    );
  }

  @override
  Future<void> setDone({
    required String coupleId,
    required String userId,
    required BucketItem item,
    required bool done,
  }) async {
    if (error != null) throw error!;
    toggled.add((item.id, done));
  }

  @override
  Future<void> deleteItem(String id) async {
    if (error != null) throw error!;
    deleted.add(id);
  }
}

BucketItem _item(String id, {int day = 1, int? doneDay}) => BucketItem(
      id: id,
      coupleId: 'c',
      title: 'Item $id',
      emoji: '✨',
      createdAt: DateTime(2026, 1, day),
      doneAt: doneDay == null ? null : DateTime(2026, 2, doneDay),
    );

void main() {
  late _FakeBucketRepository repo;
  late BucketBloc bloc;

  setUp(() {
    repo = _FakeBucketRepository();
    bloc = BucketBloc(bucketRepository: repo, loadTimeout: const Duration(milliseconds: 50))
      ..add(BucketOpened(coupleId: 'c', userId: 'u'));
  });

  tearDown(() => bloc.close());

  Future<BucketReady> ready() async => await bloc.stream.firstWhere((s) => s is BucketReady) as BucketReady;

  test('starts empty and shows an empty list after the wait when nothing arrives', () async {
    final s = await ready();
    expect(s.items, isEmpty);
  });

  test('shows to-do items newest first, then done items most recently done first', () async {
    await pumpEventQueue();
    repo.changes.add([_item('old', day: 1), _item('done1', day: 2, doneDay: 1), _item('new', day: 3), _item('done2', day: 4, doneDay: 5)]);
    final s = await ready();
    expect(s.items.map((i) => i.id), ['new', 'old', 'done2', 'done1']);
    expect(s.doneCount, 2);
  });

  test('adding while online relies on the live list', () async {
    await ready();
    bloc.add(ItemAdded(title: '  Go to Paris  ', emoji: '✈️'));
    await pumpEventQueue();
    expect(repo.added, ['Go to Paris']);
  });

  test('a blank title is ignored', () async {
    await ready();
    bloc.add(ItemAdded(title: '   ', emoji: '✨'));
    await pumpEventQueue();
    expect(repo.added, isEmpty);
  });

  test('an offline add is shown as waiting, then dropped once the server list has it', () async {
    await ready();
    repo.sentNow = false;
    bloc.add(ItemAdded(title: 'Go to Paris', emoji: '✈️'));
    final waiting = await bloc.stream.firstWhere((s) => s is BucketReady && s.pendingIds.isNotEmpty) as BucketReady;
    expect(waiting.items.single.title, 'Go to Paris');
    expect(waiting.notice, contains('offline'));

    repo.changes.add([_item('new-1')]);
    final synced = await bloc.stream.firstWhere((s) => s is BucketReady && s.pendingIds.isEmpty) as BucketReady;
    expect(synced.items.single.id, 'new-1');
  });

  test('toggling asks the repository to flip the done state', () async {
    await ready();
    bloc.add(ItemToggled(_item('a')));
    bloc.add(ItemToggled(_item('b', doneDay: 1)));
    await pumpEventQueue();
    expect(repo.toggled, [('a', true), ('b', false)]);
  });

  test('a failed toggle reports an error', () async {
    await ready();
    repo.error = Exception('offline');
    bloc.add(ItemToggled(_item('a')));
    final s = await bloc.stream.firstWhere((s) => s is BucketReady && s.notice != null) as BucketReady;
    expect(s.notice, contains('Could not update'));
  });

  test('removing deletes by id; a failure reports an error', () async {
    await ready();
    repo.changes.add([_item('a'), _item('keep')]);
    await bloc.stream.firstWhere((s) => s is BucketReady && s.items.length == 2);
    bloc.add(ItemRemoved('a'));
    final after = await bloc.stream.firstWhere((s) => s is BucketReady && s.items.length == 1) as BucketReady;
    expect(repo.deleted, ['a']);
    expect(after.items.single.id, 'keep', reason: 'the item disappears without waiting for a delete event');

    repo.error = Exception('offline');
    bloc.add(ItemRemoved('b'));
    final s = await bloc.stream.firstWhere((s) => s is BucketReady && s.notice != null) as BucketReady;
    expect(s.notice, contains('Could not delete'));
  });
}
