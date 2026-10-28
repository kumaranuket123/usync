import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/entities/canvas_stroke.dart';
import 'package:usync/domain/repositories/i_canvas_repository.dart';
import 'package:usync/domain/repositories/i_memory_repository.dart';
import 'package:usync/presentation/features/canvas/bloc/canvas_bloc.dart';

class _Canvas implements ICanvasRepository {
  final partner = StreamController<bool>.broadcast();
  final liveFlags = <bool>[];
  final chunks = <List<Offset>>[];

  @override
  Future<void> pushStroke(CanvasStroke stroke, {bool live = true}) async => liveFlags.add(live);
  @override
  Future<void> pushStrokeChunk(String coupleId, String strokeId, int seq, List<Offset> points) async => chunks.add(points);
  @override
  Future<void> completeStroke(String coupleId, String strokeId) async {}
  @override
  Future<void> flushStrokes() async {}
  @override
  Stream<CanvasStroke> watchRemoteStrokes(String coupleId, String excludeUserId) => const Stream.empty();
  @override
  Future<bool> isReady(String coupleId) async => true;
  @override
  Future<int> clearCanvas(String coupleId) async => 0;
  @override
  Stream<int> watchCanvasCleared(String coupleId) => const Stream.empty();
  @override
  Future<void> enterCanvas(String coupleId, String userId) async {}
  @override
  Future<void> leaveCanvas(String coupleId, String userId) async {}
  @override
  Stream<bool> watchPartnerOnCanvas(String coupleId, String partnerUserId) => partner.stream;
}

class _Memories extends Fake implements IMemoryRepository {}

void main() {
  late _Canvas repo;
  late CanvasBloc bloc;

  setUp(() async {
    repo = _Canvas();
    bloc = CanvasBloc(canvasRepository: repo, memoryRepository: _Memories());
    bloc.add(CanvasMounted(coupleId: 'c1', userId: 'u1', partnerUserId: 'u2'));
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => bloc.close());

  Future<void> settle([int ms = 0]) => Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> draw({int holdMs = 0}) async {
    bloc.add(StrokeStarted(const Offset(1, 1)));
    await settle();
    bloc.add(StrokeUpdated(const Offset(2, 2)));
    await settle(holdMs);
    bloc.add(StrokeUpdated(const Offset(3, 3)));
    bloc.add(StrokeEnded());
    await settle();
  }

  test('with the partner away nothing is sent live: one chunk with the whole stroke, for saving', () async {
    await draw(holdMs: 400);

    expect(repo.liveFlags, [false]);
    expect(repo.chunks, hasLength(1), reason: 'no timed chunks while nobody is watching');
    expect(repo.chunks.single, const [Offset(1, 1), Offset(2, 2), Offset(3, 3)]);
  });

  test('with the partner on the canvas it is sent live in quick chunks', () async {
    repo.partner.add(true);
    await settle();

    await draw(holdMs: 400);

    expect(repo.liveFlags, [true]);
    expect(repo.chunks.length, greaterThan(1), reason: 'points go out while drawing, not only at the end');
    expect(repo.chunks.expand((c) => c).toList(), const [Offset(1, 1), Offset(2, 2), Offset(3, 3)]);
  });

  test('a partner who arrives mid-stroke only affects the next stroke', () async {
    bloc.add(StrokeStarted(const Offset(1, 1)));
    await settle();
    repo.partner.add(true);
    await settle();
    bloc.add(StrokeEnded());
    await settle();
    expect(repo.liveFlags, [false]);

    await draw();
    expect(repo.liveFlags, [false, true]);
  });
}
