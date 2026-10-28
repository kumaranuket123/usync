import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/crypto/content_cipher.dart';
import '../../domain/entities/canvas_stroke.dart';

/// Seals and opens the drawing's content, in the database and on the live channel.
///
/// A saved stroke is one value (`canvas_strokes.enc`) bound to its row; a live message is bound to the
/// stroke id and its part (`start`, or `chunk:<seq>`), so none can be moved to another stroke or part.
/// Who drew it, the stroke id and when stay readable.
class CanvasStrokeCodec {
  const CanvasStrokeCodec(this.cipher);
  final ContentCipher cipher;

  static const _table     = 'canvas_strokes';
  static const _liveTable = 'canvas_live';

  /// Seals a finished stroke for its row.
  Future<String> sealStroke(String coupleId, String id, {required int color, required double width, required bool isEraser, required List<double> points}) =>
      cipher.sealJson({'color': color, 'width': width, 'is_eraser': isEraser, 'points': points}, coupleId: coupleId, table: _table, rowId: id);

  /// A stroke from a row: sealed ones are opened, older readable ones are used as they are. Null when
  /// this phone cannot read it (no key yet, or it was changed), so one bad row never hides the others.
  Future<CanvasStroke?> openRow(Map<String, dynamic> row) async {
    try {
      final sealed = row['enc'] as String?;
      final Map<String, dynamic> c;
      if (ContentCipher.isEncrypted(sealed)) {
        c = await cipher.openJson(sealed!, coupleId: row['couple_id'] as String, table: _table, rowId: row['id'] as String);
      } else {
        c = row;
      }
      final flat = c['points'] as List;
      return CanvasStroke(
        id:         row['id']        as String,
        coupleId:   row['couple_id'] as String,
        userId:     row['user_id']   as String,
        color:      Color((c['color'] as num).toInt()),
        width:      (c['width'] as num).toDouble(),
        timestamp:  DateTime.parse(row['created_at'] as String),
        points:     [for (var i = 0; i + 1 < flat.length; i += 2) Offset((flat[i] as num).toDouble(), (flat[i + 1] as num).toDouble())],
        isEraser:   c['is_eraser'] as bool? ?? false,
        isComplete: true,
      );
    } catch (e) {
      debugPrint('Could not read a stroke: ${e.runtimeType}');
      return null;
    }
  }

  Future<String> sealLiveStart(String coupleId, String id, {required int color, required double width, required bool isEraser}) =>
      cipher.sealJson({'color': color, 'width': width, 'is_eraser': isEraser}, coupleId: coupleId, table: _liveTable, rowId: id, field: 'start');

  Future<Map<String, dynamic>> openLiveStart(String coupleId, String id, String sealed) =>
      cipher.openJson(sealed, coupleId: coupleId, table: _liveTable, rowId: id, field: 'start');

  Future<String> sealLiveChunk(String coupleId, String id, int seq, List<dynamic> points) =>
      cipher.sealJson({'pts': points}, coupleId: coupleId, table: _liveTable, rowId: id, field: 'chunk:$seq');

  Future<List<dynamic>> openLiveChunk(String coupleId, String id, int seq, String sealed) async =>
      (await cipher.openJson(sealed, coupleId: coupleId, table: _liveTable, rowId: id, field: 'chunk:$seq'))['pts'] as List;
}
