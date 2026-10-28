import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/content_cipher.dart';
import '../datasources/local/prefs_source.dart';
import '../datasources/remote/storage_source.dart';
import '../models/canvas_stroke_codec.dart';
import 'memory_repository.dart';

/// Seals the content this person wrote BEFORE encryption existed (it is still readable on the server).
///
/// Each phone only seals the rows it wrote itself, through `seal_row` / `seal_answer`, which refuse anyone
/// else's row and replace the readable content with the same placeholders new rows use. It is idempotent
/// and safe to stop at any point: a row is sealed whole or not at all, and the next run carries on. The
/// content shapes here are exactly what each repository reads back (a test checks every one).
class LegacyContentSealer {
  LegacyContentSealer({
    required this.client,
    required this.cipher,
    required this.storage,
    required this.prefs,
    required this.whoAmI,
  }) : _strokes = CanvasStrokeCodec(cipher);

  final SupabaseClient      client;
  final ContentCipher       cipher;
  final StorageSource       storage;
  final PrefsSource         prefs;
  /// The signed-in person and their couple, or null.
  final Future<({String userId, String coupleId})?> Function() whoAmI;
  final CanvasStrokeCodec   _strokes;

  static const _minGap = Duration(minutes: 15);
  DateTime? _last;
  Future<int>? _running;

  /// Runs at most one pass at a time, and not more often than every few minutes. Never throws.
  Future<int> runIfDue() {
    final last = _last;
    if (_running != null) return _running!;
    if (last != null && DateTime.now().difference(last) < _minGap) return Future.value(0);
    _last = DateTime.now();
    return _running = _run().whenComplete(() {
      _running = null;
    });
  }

  Future<int> _run() async {
    try {
      final me = await whoAmI();
      if (me == null || !await cipher.isReady(me.coupleId)) return 0;
      return await sealAll(me.coupleId, me.userId);
    } catch (e) {
      debugPrint('Sealing older content stopped: ${e.runtimeType}');
      return 0;
    }
  }

  /// One pass over everything this person wrote. Returns how many rows were sealed.
  Future<int> sealAll(String coupleId, String userId) async {
    var sealed = 0;
    sealed += await _moods(coupleId, userId);
    sealed += await _bucket(coupleId, userId);
    sealed += await _answers(coupleId, userId);
    sealed += await _memories(coupleId, userId);
    sealed += await _milestones(coupleId, userId);
    sealed += await _strokesOf(coupleId, userId);
    sealed += await _nextMeet(coupleId);
    await _ownLocation(userId);
    return sealed;
  }

  /// Seals each row; one that fails is skipped and tried again next time, except that a missing couple key
  /// stops the whole pass.
  Future<int> _each(List<Map<String, dynamic>> rows, Future<bool> Function(Map<String, dynamic> row) seal) async {
    var n = 0;
    for (final row in rows) {
      try {
        if (await seal(row)) n++;
      } on EncryptionNotReady {
        rethrow;
      } catch (e) {
        debugPrint('Could not seal an older row: ${e.runtimeType}');
      }
    }
    return n;
  }

  Future<bool> _call(String table, String id, String enc, {String? imagePath}) async =>
      await client.rpc('seal_row', params: {'p_table': table, 'p_id': id, 'p_enc': enc, 'p_image_path': imagePath}) == true;

  Future<int> _moods(String coupleId, String userId) async {
    final rows = await client.from('moods').select().eq('couple_id', coupleId).eq('user_id', userId).isFilter('enc', null);
    return _each(rows, (r) async => _call('moods', r['id'] as String, await cipher.sealJson(
          {'type': r['type'], 'label': r['custom_label'], 'emoji': r['custom_emoji']},
          coupleId: coupleId, table: 'moods', rowId: r['id'] as String)));
  }

  Future<int> _bucket(String coupleId, String userId) async {
    final rows = await client.from('bucket_items').select().eq('couple_id', coupleId).eq('created_by', userId).isFilter('enc', null);
    return _each(rows, (r) async => _call('bucket_items', r['id'] as String, await cipher.sealJson(
          {'title': r['title'], 'emoji': r['emoji'], 'note': r['note']},
          coupleId: coupleId, table: 'bucket_items', rowId: r['id'] as String)));
  }

  Future<int> _answers(String coupleId, String userId) async {
    final rows = await client.from('question_answers').select().eq('couple_id', coupleId).eq('user_id', userId).not('answer', 'like', 'u1:%');
    return _each(rows, (r) async {
      final day = r['day'] as String;
      final sealed = await cipher.sealText(r['answer'] as String,
          coupleId: coupleId, table: 'question_answers', rowId: '$userId:$day', field: 'answer');
      return await client.rpc('seal_answer', params: {'p_couple': coupleId, 'p_day': day, 'p_enc': sealed}) == true;
    });
  }

  Future<int> _memories(String coupleId, String userId) async {
    final rows = await client.from('memories').select().eq('couple_id', coupleId).eq('created_by_user_id', userId).isFilter('enc', null);
    return _each(rows, (r) async {
      final id = r['id'] as String;
      final oldPath = r['thumbnail_url'] as String?;
      String? newPath;
      // A readable picture is downloaded, sealed and uploaded under its new name first; the old object
      // is deleted only once the row points at the new one.
      if (oldPath != null && oldPath.isNotEmpty && !oldPath.endsWith('.enc')) {
        try {
          final plain = await storage.download(oldPath);
          final sealedImage = await cipher.sealBytes(plain, coupleId: coupleId, table: 'memories', rowId: id, field: 'image');
          newPath = MemoryRepository.sealedPath(coupleId, id);
          await storage.uploadSealedAt(newPath, sealedImage);
        } on StorageException catch (e) {
          if (e.statusCode != '404') rethrow;
          newPath = null; // the picture is gone: seal the text and leave the (dead) path as it is
        }
      }
      final enc = await cipher.sealJson({'title': r['title'], 'emoji': r['thumbnail_emoji']}, coupleId: coupleId, table: 'memories', rowId: id);
      final done = await _call('memories', id, enc, imagePath: newPath);
      if (done && newPath != null && oldPath != null) {
        try {
          await storage.remove(oldPath);
        } catch (_) {} // an orphan, not a leak of anything new: it is removed with the couple's folder
      }
      return done;
    });
  }

  Future<int> _milestones(String coupleId, String userId) async {
    final rows = await client.from('milestones').select().eq('couple_id', coupleId).eq('created_by', userId).eq('type', 'custom').isFilter('enc', null);
    return _each(rows, (r) async => _call('milestones', r['id'] as String, await cipher.sealJson(
          {
            'title':         r['title'],
            'note':          r['note'],
            'emoji':         r['emoji'],
            'repeatsYearly': r['repeats_yearly'] == true,
            'occurredAt':    DateTime.parse(r['occurred_at'] as String).toUtc().toIso8601String(),
          },
          coupleId: coupleId, table: 'milestones', rowId: r['id'] as String)));
  }

  Future<int> _strokesOf(String coupleId, String userId) async {
    final rows = await client.from('canvas_strokes').select().eq('couple_id', coupleId).eq('user_id', userId).isFilter('enc', null);
    return _each(rows, (r) async => _call('canvas_strokes', r['id'] as String, await _strokes.sealStroke(
          coupleId, r['id'] as String,
          color: (r['color'] as num).toInt(),
          width: (r['width'] as num).toDouble(),
          isEraser: r['is_eraser'] as bool? ?? false,
          points: [for (final v in (r['points'] as List)) (v as num).toDouble()])));
  }

  /// The shared next-meeting date: either partner may seal it (no notification: nothing new happened).
  Future<int> _nextMeet(String coupleId) async {
    final row = await client.from('couples').select('next_meet_on, next_meet_enc').eq('id', coupleId).maybeSingle();
    final day = row?['next_meet_on'] as String?;
    if (day == null || row?['next_meet_enc'] != null) return 0;
    final sealed = await cipher.sealJson({'day': day}, coupleId: coupleId, table: 'couples', rowId: coupleId, field: 'next_meet');
    await client.rpc('set_next_meet_enc', params: {'p_couple': coupleId, 'p_enc': sealed});
    return 1;
  }

  /// An older readable location. While sharing is on the next refresh replaces it with a sealed one; if
  /// sharing is off there is no reason to keep a stale readable position, so it is removed.
  Future<void> _ownLocation(String userId) async {
    if (prefs.locationSharing) return;
    try {
      await client.from('locations').delete().eq('user_id', userId).isFilter('enc', null);
    } catch (_) {}
  }
}
