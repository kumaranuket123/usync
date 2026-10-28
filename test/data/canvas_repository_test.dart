import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/data/datasources/remote/couple_channel_source.dart';
import 'package:usync/data/models/canvas_stroke_codec.dart';
import 'package:usync/data/repositories/canvas_repository.dart';
import 'package:usync/domain/entities/canvas_stroke.dart';
import 'package:usync/domain/repositories/i_canvas_repository.dart';

import '../support/test_cipher.dart';
import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late LocalStorage local;
  late CoupleChannelSource channels;
  late ContentCipher cipher;
  late CanvasRepository repo;

  CanvasRepository build(ContentCipher c, {Duration catchUpEvery = const Duration(seconds: 4)}) => CanvasRepository(
        client: backend.client,
        channelSource: channels,
        outbox: local.outbox,
        cipher: c,
        catchUpEvery: catchUpEvery,
      );

  final stroke = CanvasStroke(
    id: 's1',
    coupleId: 'c1',
    userId: 'u1',
    color: const Color(0xFFFF6EC7),
    width: 3,
    timestamp: DateTime.now(),
  );

  setUp(() async {
    backend = FakeBackend();
    local = LocalStorage();
    await local.setUp();
    channels = CoupleChannelSource(client: backend.client);
    cipher = await readyCipher();
    repo = build(cipher);
  });

  tearDown(() async {
    channels.close();
    await local.tearDown();
    await backend.dispose();
  });

  /// Draws one stroke and saves it, like the canvas does.
  Future<void> drawAndSave() async {
    await repo.pushStroke(stroke);
    await repo.pushStrokeChunk('c1', 's1', 0, const [Offset(10, 20), Offset(30, 40)]);
    await repo.completeStroke('c1', 's1');
    await repo.flushStrokes();
  }

  Recorded saved() => backend.requests.lastWhere((r) => r.path.endsWith('/canvas_strokes') && r.method == 'POST');

  test('a finished stroke is saved only as ciphertext', () async {
    backend.respond((_) => FakeBackend.ok([], status: 201));

    await drawAndSave();

    final rows = (saved().json as List).cast<Map<String, dynamic>>();
    final row = rows.single;
    expect(row['id'], 's1');
    expect(row['user_id'], 'u1');
    expect(row['enc'], startsWith('u1:'));
    for (final readable in ['color', 'width', 'points', 'is_eraser']) {
      expect(row.containsKey(readable), isFalse, reason: '$readable must not be sent readable');
    }

    final opened = await CanvasStrokeCodec(cipher).openRow({...row, 'couple_id': 'c1'});
    expect(opened!.color, const Color(0xFFFF6EC7));
    expect(opened.points, const [Offset(10, 20), Offset(30, 40)]);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('live messages carry no readable colour, width or points', () async {
    backend.respond((_) => FakeBackend.ok([], status: 201));

    await drawAndSave();

    final live = backend.requests.where((r) => r.path.contains('/realtime/') && r.body.isNotEmpty).map((r) => r.body).join('\n');
    expect(live, isNotEmpty, reason: 'the live events went out over the HTTP fallback');
    expect(live, contains('stroke_start'));
    expect(live, contains('stroke_chunk'));
    expect(live, isNot(contains('"color"')));
    expect(live, isNot(contains('"width"')));
    expect(live, isNot(contains('"pts"')));
    expect(live, isNot(contains('"is_eraser"')));
    expect(live, contains('"enc"'));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('without the couple key a finished stroke is refused and nothing is saved or queued', () async {
    repo = build(notReadyCipher());
    backend.respond((_) => FakeBackend.ok([], status: 201));

    await repo.pushStroke(stroke).then((_) {}, onError: (_) {});
    await repo.pushStrokeChunk('c1', 's1', 0, const [Offset(1, 1)]).then((_) {}, onError: (_) {});
    await expectLater(repo.completeStroke('c1', 's1'), throwsA(isA<EncryptionNotReady>()));
    await repo.flushStrokes();

    expect(backend.requests.where((r) => r.path.endsWith('/canvas_strokes')), isEmpty);
    expect(local.outbox.pending, 0);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a stroke queued by an older version (readable) is sealed before it is sent', () async {
    backend.respond((_) => FakeBackend.ok([], status: 201));
    // What an earlier version put in the outbox.
    await local.outbox.submit('strokes', {
      'items': [
        {
          'id': 's9', 'coupleId': 'c1', 'userId': 'u1', 'color': 0xFF00FF00, 'width': 5.0,
          'isEraser': false, 'points': [1.0, 2.0], 'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      ],
    });

    final row = ((saved().json) as List).single as Map<String, dynamic>;
    expect(row['enc'], startsWith('u1:'));
    expect(row.containsKey('points'), isFalse);
    expect(row.containsKey('color'), isFalse);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('isReady follows the couple key', () async {
    expect(await repo.isReady('c1'), isTrue);
    expect(await build(notReadyCipher()).isReady('c1'), isFalse);
  });

  group('strokes the partner saves after the canvas was opened', () {
    Future<Map<String, dynamic>> savedRow(String id, String userId, {ContentCipher? by}) async => {
          'id': id,
          'couple_id': 'c1',
          'user_id': userId,
          'color': null,
          'width': null,
          'points': null,
          'is_eraser': false,
          'created_at': '2026-03-01T10:00:00Z',
          'enc': await CanvasStrokeCodec(by ?? cipher).sealStroke('c1', id, color: 0xFF112233, width: 3, isEraser: false, points: [1, 2, 3, 4]),
        };

    /// Serves the saved strokes from [rows] (which a test can add to while the canvas is open), by the three
    /// kinds of read the repository makes.
    void serve(List<Map<String, dynamic>> rows) => backend.respond((r) {
          if (!r.path.endsWith('/canvas_strokes') || r.method != 'GET') return FakeBackend.ok([], status: 200);
          if (r.query['select'] == 'id') return FakeBackend.ok([for (final row in rows) {'id': row['id']}]);
          final inFilter = r.query['id'];
          if (inFilter != null) return FakeBackend.ok([for (final row in rows) if (inFilter.contains(row['id'] as String)) row]);
          return FakeBackend.ok(rows);
        });

    test('a stroke saved while the canvas is open is shown without reopening it', () async {
      final rows = <Map<String, dynamic>>[];
      serve(rows);
      repo = build(cipher, catchUpEvery: const Duration(milliseconds: 300));

      final shown = <CanvasStroke>[];
      final sub = repo.watchRemoteStrokes('c1', 'u1').listen(shown.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(seconds: 7)); // the canvas opened with nothing saved yet
      expect(shown, isEmpty);

      rows.add(await savedRow('s-partner', 'u2')); // the partner's batch reaches the server a moment later
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(shown.map((s) => s.id), ['s-partner']);
      expect(shown.single.userId, 'u2');
      expect(shown.single.points, const [Offset(1, 2), Offset(3, 4)]);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a stroke is shown once, however many times the server is asked', () async {
      final rows = [await savedRow('s1', 'u2')];
      serve(rows);
      repo = build(cipher, catchUpEvery: const Duration(milliseconds: 300));

      final shown = <CanvasStroke>[];
      final sub = repo.watchRemoteStrokes('c1', 'u1').listen(shown.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(seconds: 8));

      expect(shown.map((s) => s.id), ['s1']);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('strokes this phone cannot read are reported once, not silently dropped', () async {
      final rows = [await savedRow('s1', 'u2', by: await readyCipher()), await savedRow('s2', 'u2', by: await readyCipher())];
      serve(rows);
      repo = build(cipher, catchUpEvery: const Duration(milliseconds: 300));

      final shown = <CanvasStroke>[];
      final errors = <Object>[];
      final sub = repo.watchRemoteStrokes('c1', 'u1').listen(shown.add, onError: errors.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(seconds: 8));

      expect(shown, isEmpty);
      expect(errors.whereType<StrokesUnreadable>(), hasLength(1));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
