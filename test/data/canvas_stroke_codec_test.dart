import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/data/models/canvas_stroke_codec.dart';

import '../support/test_cipher.dart';

void main() {
  late ContentCipher cipher;
  late CanvasStrokeCodec codec;

  setUp(() async {
    cipher = await readyCipher();
    codec = CanvasStrokeCodec(cipher);
  });

  Future<Map<String, dynamic>> row(String id, {String coupleId = 'c1', CanvasStrokeCodec? by}) async => {
        'id': id,
        'couple_id': coupleId,
        'user_id': 'u1',
        'color': null,
        'width': null,
        'points': null,
        'is_eraser': false,
        'created_at': '2026-03-01T10:00:00Z',
        'enc': await (by ?? codec).sealStroke(coupleId, id, color: 0xFFFF6EC7, width: 3, isEraser: true, points: [1, 2, 3.5, 4.5]),
      };

  test('a saved stroke is sealed, hides its content, and opens to the same stroke', () async {
    final r = await row('s1');
    expect(r['enc'], startsWith('u1:'));

    final stroke = (await codec.openRow(r))!;
    expect(stroke.id, 's1');
    expect(stroke.userId, 'u1');
    expect(stroke.color, const Color(0xFFFF6EC7));
    expect(stroke.width, 3);
    expect(stroke.isEraser, isTrue);
    expect(stroke.points, const [Offset(1, 2), Offset(3.5, 4.5)]);
    expect(stroke.isComplete, isTrue);
  });

  test('an older readable stroke is still opened', () async {
    final stroke = (await codec.openRow({
      'id': 's1', 'couple_id': 'c1', 'user_id': 'u1', 'color': 0xFF112233, 'width': 4.0,
      'points': [5, 6], 'is_eraser': false, 'created_at': '2026-03-01T10:00:00Z', 'enc': null,
    }))!;
    expect(stroke.color, const Color(0xFF112233));
    expect(stroke.points, const [Offset(5, 6)]);
  });

  test('a stroke this phone cannot read is skipped, not thrown', () async {
    final foreign = CanvasStrokeCodec(await readyCipher());
    expect(await codec.openRow(await row('s1', by: foreign)), isNull);
    expect(await CanvasStrokeCodec(notReadyCipher()).openRow(await row('s1')), isNull);
  });

  test('a stroke copied onto another row or couple does not open', () async {
    final r = await row('s1');
    expect(await codec.openRow({...r, 'id': 's2'}), isNull);
    final other = await readyCipher(coupleIds: const ['c1', 'c2']);
    expect(await CanvasStrokeCodec(other).openRow({...r, 'couple_id': 'c2'}), isNull);
  });

  group('live messages', () {
    test('start and chunks round-trip and are bound to their stroke and part', () async {
      final start = await codec.sealLiveStart('c1', 's1', color: 0xFF000001, width: 30, isEraser: true);
      final chunk = await codec.sealLiveChunk('c1', 's1', 2, [1.0, 2.0, 3.0, 4.0]);

      expect(await codec.openLiveStart('c1', 's1', start), {'color': 0xFF000001, 'width': 30, 'is_eraser': true});
      expect(await codec.openLiveChunk('c1', 's1', 2, chunk), [1.0, 2.0, 3.0, 4.0]);

      await expectLater(codec.openLiveStart('c1', 's2', start), throwsA(anything), reason: 'another stroke');
      await expectLater(codec.openLiveChunk('c1', 's1', 3, chunk), throwsA(anything), reason: 'another chunk');
      await expectLater(codec.openLiveChunk('c1', 's2', 2, chunk), throwsA(anything));
      await expectLater(codec.openLiveStart('c1', 's1', chunk), throwsA(anything), reason: 'a chunk is not a start');
    });

    test('a live message is not a saved stroke', () async {
      final live = await codec.sealLiveChunk('c1', 's1', 0, [1.0, 2.0]);
      final r = {...await row('s1'), 'enc': live};
      expect(await codec.openRow(r), isNull);
    });

    test('without the couple key nothing can be sealed', () async {
      await expectLater(CanvasStrokeCodec(notReadyCipher()).sealLiveStart('c1', 's1', color: 1, width: 1, isEraser: false), throwsA(isA<EncryptionNotReady>()));
    });
  });
}
