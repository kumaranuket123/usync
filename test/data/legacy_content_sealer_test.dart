import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/data/datasources/local/prefs_source.dart';
import 'package:usync/data/datasources/remote/couple_channel_source.dart';
import 'package:usync/data/datasources/remote/storage_source.dart';
import 'package:usync/data/models/canvas_stroke_codec.dart';
import 'package:usync/data/repositories/bucket_repository.dart';
import 'package:usync/data/repositories/couple_repository.dart';
import 'package:usync/data/repositories/legacy_content_sealer.dart';
import 'package:usync/data/repositories/memory_repository.dart';
import 'package:usync/data/repositories/milestone_repository.dart';
import 'package:usync/data/repositories/mood_repository.dart';
import 'package:usync/data/datasources/local/identity_cache.dart';
import 'package:usync/data/repositories/question_repository.dart';
import 'package:usync/domain/entities/daily_question.dart';
import 'package:usync/domain/entities/mood.dart';

import '../support/test_cipher.dart';
import 'repository_harness.dart';

const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4];

/// The file inside a multipart upload.
Uint8List _filePart(List<int> body) {
  int find(List<int> h, List<int> n, {bool last = false}) {
    final range = last ? [for (var i = h.length - n.length; i >= 0; i--) i] : [for (var i = 0; i + n.length <= h.length; i++) i];
    for (final i in range) {
      var hit = true;
      for (var j = 0; j < n.length; j++) {
        if (h[i + j] != n[j]) { hit = false; break; }
      }
      if (hit) return i;
    }
    return -1;
  }

  final sep = utf8.encode('\r\n\r\n');
  final named = find(body, utf8.encode('filename='));
  final start = named + find(body.sublist(named), sep) + sep.length;
  return Uint8List.fromList(body.sublist(start, find(body, utf8.encode('\r\n--'), last: true)));
}

void main() {
  late FakeBackend backend;
  late LocalStorage local;
  late SharedPreferences prefs;
  late ContentCipher cipher;
  late LegacyContentSealer sealer;
  late RecordingNotifications notifications;
  late CoupleChannelSource channels;

  /// Rows the fake server returns per table for the sealer's reads.
  final tables = <String, List<Map<String, dynamic>>>{};
  var sealResult = true;
  var imageDownload = () => http.Response.bytes(_png, 200);

  LegacyContentSealer build(ContentCipher c) => LegacyContentSealer(
        client: backend.client,
        cipher: c,
        storage: StorageSource(client: backend.client),
        prefs: PrefsSource(prefs: prefs),
        whoAmI: () async => (userId: 'u1', coupleId: 'c1'),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    backend = FakeBackend();
    local = LocalStorage();
    await local.setUp();
    notifications = RecordingNotifications();
    channels = CoupleChannelSource(client: backend.client);
    cipher = await readyCipher();
    sealer = build(cipher);
    tables.clear();
    sealResult = true;
    imageDownload = () => http.Response.bytes(_png, 200);
    backend.respond((r) {
      if (r.path.contains('/rpc/')) return FakeBackend.ok(sealResult);
      if (r.path.contains('/storage/v1/object/')) {
        return r.method == 'GET' ? imageDownload() : FakeBackend.ok({'Key': 'x'});
      }
      final table = r.path.split('/').last;
      if (table == 'couples') return FakeBackend.ok(tables['couples']?.first);
      if (r.method == 'DELETE') return FakeBackend.ok([]);
      return FakeBackend.ok(tables[table] ?? []);
    });
  });

  tearDown(() async {
    channels.close();
    await local.tearDown();
    await backend.dispose();
  });

  List<Recorded> rpcs(String name) => backend.requests.where((r) => r.path.endsWith('/rpc/$name')).toList();
  Map<String, dynamic> sentTo(String name, [int i = 0]) => rpcs(name)[i].json as Map<String, dynamic>;

  Map<String, dynamic> asSealedRow(Map<String, dynamic> legacy, String enc, Map<String, dynamic> placeholders) => {...legacy, ...placeholders, 'enc': enc};

  test('a legacy mood is sealed and reads back as the same mood', () async {
    final row = {'id': 'm1', 'couple_id': 'c1', 'user_id': 'u1', 'type': 'custom', 'custom_label': 'Missing you', 'custom_emoji': '🥺', 'sent_at': '2026-03-01T10:00:00Z', 'enc': null};
    tables['moods'] = [row];

    expect(await sealer.sealAll('c1', 'u1'), 1);

    final sent = sentTo('seal_row');
    expect(sent['p_table'], 'moods');
    expect(sent['p_id'], 'm1');
    expect(bodyText(sent), isNot(contains('Missing')));
    final reader = MoodRepository(client: backend.client, notifications: notifications, outbox: local.outbox, sessionCache: local.sessionCache, cipher: cipher);
    tables['moods'] = [asSealedRow(row, sent['p_enc'] as String, {'type': 'custom', 'custom_label': null, 'custom_emoji': null})];
    final moods = await reader.getMoodsSince('c1', DateTime(2026));
    expect(moods.single.type, MoodType.custom);
    expect(moods.single.customLabel, 'Missing you');
    expect(moods.single.customEmoji, '🥺');
  });

  test('a legacy bucket item is sealed and reads back', () async {
    final row = {'id': 'b1', 'couple_id': 'c1', 'title': 'See the aurora', 'emoji': '🌌', 'note': 'Iceland', 'created_by': 'u1', 'created_at': '2026-02-01T10:00:00Z', 'done_at': null, 'done_by': null, 'enc': null};
    tables['bucket_items'] = [row];

    await sealer.sealAll('c1', 'u1');

    final sent = sentTo('seal_row');
    expect(sent['p_table'], 'bucket_items');
    expect(bodyText(sent), isNot(contains('aurora')));
    final reader = BucketRepository(client: backend.client, notifications: notifications, outbox: local.outbox, sessionCache: local.sessionCache, cipher: cipher);
    await local.sessionCache.put('bucket:c1', [asSealedRow(row, sent['p_enc'] as String, {'title': '🔒', 'emoji': '🔒', 'note': null})]);
    final item = (await reader.watchItems('c1').first).single;
    expect((item.title, item.emoji, item.note), ('See the aurora', '🌌', 'Iceland'));
  });

  test('a legacy answer is sealed for its day and reads back', () async {
    final q = DailyQuestion.forDay(DateTime(2026, 3, 4));
    tables['question_answers'] = [
      {'couple_id': 'c1', 'user_id': 'u1', 'day': q.day, 'question_idx': q.index, 'answer': 'Your laugh', 'created_at': '2026-03-04T10:00:00Z'},
    ];

    await sealer.sealAll('c1', 'u1');

    final sent = sentTo('seal_answer');
    expect((sent['p_couple'], sent['p_day']), ('c1', q.day));
    expect(bodyText(sent), isNot(contains('laugh')));
    backend.respond((_) => FakeBackend.ok([
          {'my_answer': sent['p_enc'], 'partner_answered': false, 'partner_answer': null},
        ]));
    final reader = QuestionRepository(client: backend.client, notifications: notifications, cipher: cipher);
    expect((await reader.getState('c1', q, userId: 'u1', partnerId: 'u2')).myAnswer, 'Your laugh');
  });

  group('memories', () {
    final row = {'id': 'mem1', 'couple_id': 'c1', 'type': 'canvas', 'thumbnail_emoji': '✏️', 'title': 'Doodle · our day', 'created_by_user_id': 'u1', 'thumbnail_url': 'c1/old.png', 'is_favourited': false, 'image_archived': false, 'created_at': '2026-03-01T10:00:00Z', 'archived_by': [], 'enc': null};

    test('the text and the picture are sealed; the picture moves to a sealed object and the old one is removed', () async {
      tables['memories'] = [row];

      await sealer.sealAll('c1', 'u1');

      final uploads = backend.requests.where((r) => r.path.contains('/storage/') && r.method != 'GET').toList();
      final newPicture = uploads.firstWhere((r) => r.path.endsWith('/c1/mem1.enc'));
      expect(await cipher.openBytes(_filePart(newPicture.bodyBytes), coupleId: 'c1', table: 'memories', rowId: 'mem1', field: 'image'), _png);

      final sent = sentTo('seal_row');
      expect(sent['p_table'], 'memories');
      expect(sent['p_image_path'], 'c1/mem1.enc');
      expect(bodyText(sent), isNot(contains('our day')));
      expect(backend.requests.any((r) => r.method == 'DELETE' && r.path.contains('/storage/') ), isTrue, reason: 'the readable object is removed afterwards');

      final reader = MemoryRepository(client: backend.client, storage: StorageSource(client: backend.client), notifications: notifications, outbox: local.outbox, prefs: PrefsSource(prefs: prefs), cipher: cipher);
      backend.respond((_) => FakeBackend.ok([asSealedRow(row, sent['p_enc'] as String, {'title': '🔒', 'thumbnail_emoji': '🔒', 'thumbnail_url': 'c1/mem1.enc'})]));
      final m = (await reader.getMemories('c1')).single;
      expect((m.title, m.thumbnailEmoji, m.thumbnailUrl), ('Doodle · our day', '✏️', 'c1/mem1.enc'));
    });

    test('a picture that is already gone does not stop the text being sealed', () async {
      tables['memories'] = [row];
      imageDownload = () => FakeBackend.error('404', 'not found', status: 404);

      expect(await sealer.sealAll('c1', 'u1'), 1);
      expect(sentTo('seal_row')['p_image_path'], isNull);
    });

    test('a failed download (not "gone") leaves the row for the next run', () async {
      tables['memories'] = [row];
      imageDownload = () => FakeBackend.error('500', 'oops', status: 500);

      expect(await sealer.sealAll('c1', 'u1'), 0);
      expect(rpcs('seal_row'), isEmpty);
    });

    test('a memory with no picture is just sealed', () async {
      tables['memories'] = [{...row, 'thumbnail_url': null}];
      expect(await sealer.sealAll('c1', 'u1'), 1);
      expect(sentTo('seal_row')['p_image_path'], isNull);
      expect(backend.requests.where((r) => r.path.contains('/storage/')), isEmpty);
    });
  });

  test('a legacy custom date is sealed and reads back', () async {
    final row = {'id': 'd1', 'couple_id': 'c1', 'type': 'custom', 'title': 'Our first trip', 'occurred_at': '2026-07-14T12:00:00+00:00', 'note': 'Goa', 'linked_memory_id': null, 'emoji': '🏖️', 'repeats_yearly': true, 'created_by': 'u1', 'enc': null};
    tables['milestones'] = [row];

    await sealer.sealAll('c1', 'u1');

    final sent = sentTo('seal_row');
    expect(sent['p_table'], 'milestones');
    expect(bodyText(sent), isNot(contains('trip')));
    final reader = MilestoneRepository(client: backend.client, notifications: notifications, outbox: local.outbox, sessionCache: local.sessionCache, cipher: cipher);
    backend.respond((_) => FakeBackend.ok([asSealedRow(row, sent['p_enc'] as String, {'title': '🔒', 'note': null, 'emoji': null, 'repeats_yearly': false, 'occurred_at': '1970-01-01T12:00:00Z'})]));
    final m = (await reader.getMilestones('c1')).single;
    expect((m.title, m.note, m.emoji, m.repeatsYearly), ('Our first trip', 'Goa', '🏖️', true));
    expect(m.occurredAt, DateTime.utc(2026, 7, 14, 12));
  });

  test('a legacy stroke is sealed and reads back', () async {
    final row = {'id': 's1', 'couple_id': 'c1', 'user_id': 'u1', 'color': 0xFFFF6EC7, 'width': 3.0, 'is_eraser': true, 'points': [1, 2, 3.5, 4.5], 'created_at': '2026-03-01T10:00:00Z', 'enc': null};
    tables['canvas_strokes'] = [row];

    await sealer.sealAll('c1', 'u1');

    final sent = sentTo('seal_row');
    expect(sent['p_table'], 'canvas_strokes');
    final stroke = (await CanvasStrokeCodec(cipher).openRow(asSealedRow(row, sent['p_enc'] as String, {'color': null, 'width': null, 'points': null, 'is_eraser': false})))!;
    expect(stroke.color, const Color(0xFFFF6EC7));
    expect(stroke.isEraser, isTrue);
    expect(stroke.points, const [Offset(1, 2), Offset(3.5, 4.5)]);
  });

  test('a readable next-meeting date is sealed through its own function, without telling the partner', () async {
    tables['couples'] = [{'next_meet_on': '2026-12-12', 'next_meet_enc': null}];

    await sealer.sealAll('c1', 'u1');

    final sent = sentTo('set_next_meet_enc');
    expect(bodyText(sent), isNot(contains('2026-12')));
    final reader = CoupleRepository(client: backend.client, channelSource: channels, notifications: notifications, storage: StorageSource(client: backend.client), sessionCache: local.sessionCache, identity: IdentityCache(), cipher: cipher);
    backend.respond((_) => FakeBackend.ok({'id': 'c1', 'user_a_id': 'u1', 'user_b_id': 'u2', 'paired_at': '2026-01-01T00:00:00Z', 'next_meet_on': null, 'next_meet_enc': sent['p_enc']}));
    expect((await reader.getCouple('c1')).nextMeetOn, DateTime(2026, 12, 12));
    expect(notifications.sent, isEmpty);
  });

  test('only this person\'s rows in this couple are asked for', () async {
    tables['moods'] = [];
    await sealer.sealAll('c1', 'u1');
    final moodsRead = backend.requests.firstWhere((r) => r.path.endsWith('/moods'));
    expect(moodsRead.query['user_id'], 'eq.u1');
    expect(moodsRead.query['couple_id'], 'eq.c1');
    expect(moodsRead.query['enc'], 'is.null');
    final bucketRead = backend.requests.firstWhere((r) => r.path.endsWith('/bucket_items'));
    expect(bucketRead.query['created_by'], 'eq.u1');
  });

  test('a row the server refuses (already sealed, or not theirs) is not counted', () async {
    tables['moods'] = [{'id': 'm1', 'couple_id': 'c1', 'user_id': 'u1', 'type': 'happy', 'custom_label': null, 'custom_emoji': null, 'sent_at': '2026-03-01T10:00:00Z', 'enc': null}];
    sealResult = false;
    expect(await sealer.sealAll('c1', 'u1'), 0);
  });

  test('without the couple key nothing is sent', () async {
    tables['moods'] = [{'id': 'm1', 'couple_id': 'c1', 'user_id': 'u1', 'type': 'happy', 'custom_label': null, 'custom_emoji': null, 'sent_at': '2026-03-01T10:00:00Z', 'enc': null}];
    sealer = build(notReadyCipher());

    expect(await sealer.runIfDue(), 0);
    await expectLater(sealer.sealAll('c1', 'u1'), throwsA(isA<EncryptionNotReady>()));
    expect(rpcs('seal_row'), isEmpty);
  });

  group('older readable location', () {
    test('is removed when sharing is off', () async {
      await sealer.sealAll('c1', 'u1');
      final del = backend.requests.where((r) => r.method == 'DELETE' && r.path.endsWith('/locations')).single;
      expect(del.query['user_id'], 'eq.u1');
      expect(del.query['enc'], 'is.null', reason: 'a sealed location is never deleted');
    });

    test('is left for the next refresh to replace when sharing is on', () async {
      await prefs.setBool('location_sharing', true);
      await prefs.reload();
      expect(PrefsSource(prefs: prefs).locationSharing, isTrue, reason: 'test set-up');
      await sealer.sealAll('c1', 'u1');
      expect(backend.requests.where((r) => r.method == 'DELETE'), isEmpty);
    });
  });

  test('runIfDue runs once, then waits, and never throws', () async {
    tables['moods'] = [{'id': 'm1', 'couple_id': 'c1', 'user_id': 'u1', 'type': 'happy', 'custom_label': null, 'custom_emoji': null, 'sent_at': '2026-03-01T10:00:00Z', 'enc': null}];

    expect(await sealer.runIfDue(), 1);
    final calls = rpcs('seal_row').length;
    expect(await sealer.runIfDue(), 0, reason: 'too soon');
    expect(rpcs('seal_row').length, calls);

    backend.respond((_) => throw Exception('offline'));
    final again = LegacyContentSealer(client: backend.client, cipher: cipher, storage: StorageSource(client: backend.client), prefs: PrefsSource(prefs: prefs), whoAmI: () async => (userId: 'u1', coupleId: 'c1'));
    expect(await again.runIfDue(), 0);
  });
}
