import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/data/datasources/remote/couple_channel_source.dart';
import 'package:usync/data/models/canvas_stroke_codec.dart';
import 'package:usync/data/repositories/canvas_repository.dart';
import 'package:usync/domain/entities/canvas_stroke.dart';

import '../support/test_cipher.dart';
import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late LocalStorage local;
  late CoupleChannelSource channels;
  late ContentCipher cipher;
  late CanvasRepository repo;

  CanvasRepository build(ContentCipher c) => CanvasRepository(
        client: backend.client,
        channelSource: channels,
        outbox: local.outbox,
        cipher: c,
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
}
