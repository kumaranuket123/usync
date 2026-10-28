import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usync/data/datasources/local/prefs_source.dart';
import 'package:usync/data/datasources/remote/storage_source.dart';
import 'package:usync/data/repositories/memory_repository.dart';
import 'package:usync/domain/entities/memory.dart';
import 'package:usync/domain/entities/notification_item.dart';

import '../support/test_cipher.dart';
import 'repository_harness.dart';

/// A PNG's first eight bytes: they must never appear in what is uploaded.
const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var hit = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) { hit = false; break; }
    }
    if (hit) return true;
  }
  return false;
}

http.Response http200(List<int> bytes) => http.Response.bytes(bytes, 200);

/// The file inside a multipart upload (between the part's header and the closing boundary).
Uint8List _filePart(List<int> body) {
  final sep = utf8.encode('\r\n\r\n');
  // The form also carries small text fields (such as the cache time); the file is the part with a filename.
  final named = _indexOf(body, utf8.encode('filename='));
  final start = named + _indexOf(body.sublist(named), sep) + sep.length;
  // The closing boundary is "\r\n--<boundary>--\r\n".
  final end = _lastIndexOf(body, utf8.encode('\r\n--'));
  return Uint8List.fromList(body.sublist(start, end));
}

int _indexOf(List<int> h, List<int> n) {
  for (var i = 0; i + n.length <= h.length; i++) {
    var hit = true;
    for (var j = 0; j < n.length; j++) {
      if (h[i + j] != n[j]) { hit = false; break; }
    }
    if (hit) return i;
  }
  return -1;
}

int _lastIndexOf(List<int> h, List<int> n) {
  for (var i = h.length - n.length; i >= 0; i--) {
    var hit = true;
    for (var j = 0; j < n.length; j++) {
      if (h[i + j] != n[j]) { hit = false; break; }
    }
    if (hit) return i;
  }
  return -1;
}

void main() {
  late FakeBackend backend;
  late LocalStorage local;
  late RecordingNotifications notifications;
  late ContentCipher cipher;
  late MemoryRepository repo;
  late SharedPreferences prefs;
  final png = Uint8List.fromList([..._pngMagic, ...utf8.encode('a very secret doodle'), 1, 2, 3, 4]);

  MemoryRepository build(ContentCipher c) => MemoryRepository(
        client: backend.client,
        storage: StorageSource(client: backend.client),
        notifications: notifications,
        outbox: local.outbox,
        prefs: PrefsSource(prefs: prefs),
        cipher: c,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    backend = FakeBackend();
    local = LocalStorage();
    await local.setUp();
    notifications = RecordingNotifications();
    cipher = await readyCipher();
    repo = build(cipher);
  });

  tearDown(() async {
    await local.tearDown();
    await backend.dispose();
  });

  Recorded upload() => backend.requests.firstWhere((r) => r.path.contains('/storage/v1/object/'));
  Map<String, dynamic> insertedRow() => backend.requests.firstWhere((r) => r.path.endsWith('/memories') && r.method == 'POST').json as Map<String, dynamic>;

  group('saveDoodle', () {
    test('uploads the picture sealed, saves the title only as ciphertext, and tells the partner with a fixed sentence', () async {
      backend.respond((r) => r.path.contains('/storage/') ? FakeBackend.ok({'Key': 'memories/x'}) : FakeBackend.ok([], status: 201));

      final sentNow = await repo.saveDoodle(coupleId: 'c1', userId: 'u1', png: png, title: 'Doodle · our private joke');

      expect(sentNow, isTrue);
      final row = insertedRow();
      final id = row['id'] as String;
      final up = upload();
      expect(up.path, endsWith('/c1/$id.enc'));
      expect(up.request.headers['content-type'], isNot(contains('image/png')));
      expect(_contains(up.bodyBytes, _pngMagic), isFalse, reason: 'the picture must not be readable in the upload');
      expect(_contains(up.bodyBytes, utf8.encode('secret doodle')), isFalse);

      expect(row['title'], '🔒');
      expect(row['thumbnail_emoji'], '🔒');
      expect(row['thumbnail_url'], 'c1/$id.enc');
      expect(row['enc'], startsWith('u1:'));
      expect(bodyText(row), isNot(contains('private joke')));
      expect(await cipher.openJson(row['enc'] as String, coupleId: 'c1', table: 'memories', rowId: id), {'title': 'Doodle · our private joke', 'emoji': MemoryType.canvas.defaultEmoji});

      // The uploaded bytes are the sealed picture: they open only with this memory's binding.
      expect(await cipher.openBytes(_filePart(up.bodyBytes), coupleId: 'c1', table: 'memories', rowId: id, field: 'image'), png);
      await expectLater(cipher.openBytes(_filePart(up.bodyBytes), coupleId: 'c1', table: 'memories', rowId: 'another', field: 'image'), throwsA(anything));

      expect(notifications.sent.single.type, NotifType.doodle);
      expect(notifications.sent.single.body, 'Alex saved a new doodle ✏️');
    });

    test('without the couple key nothing is uploaded, saved or queued, and the caller is told', () async {
      repo = build(notReadyCipher());
      backend.respond((_) => FakeBackend.ok([]));

      await expectLater(repo.saveDoodle(coupleId: 'c1', userId: 'u1', png: png, title: 't'), throwsA(isA<EncryptionNotReady>()));

      expect(backend.requests, isEmpty);
      expect(local.outbox.pending, 0);
      expect(notifications.sent, isEmpty);
    });

    test('a memory that already reached the server is not added twice', () async {
      backend.respond((r) => r.path.contains('/storage/')
          ? FakeBackend.ok({'Key': 'x'})
          : FakeBackend.error('23505', 'duplicate key value'));

      await repo.saveDoodle(coupleId: 'c1', userId: 'u1', png: png, title: 't');

      expect(notifications.sent, isEmpty);
    });
  });

  group('reading', () {
    Future<Map<String, dynamic>> row(String id, {Map<String, dynamic>? content, ContentCipher? by, String? path, String coupleId = 'c1'}) async => {
          'id': id,
          'couple_id': coupleId,
          'type': 'canvas',
          'thumbnail_emoji': content == null ? '✏️' : '🔒',
          'title': content == null ? 'Old readable title' : '🔒',
          'created_by_user_id': 'u2',
          'thumbnail_url': path,
          'is_favourited': false,
          'image_archived': false,
          'created_at': '2026-03-01T10:00:00Z',
          'enc': content == null ? null : await (by ?? cipher).sealJson(content, coupleId: coupleId, table: 'memories', rowId: id),
        };

    Future<List<Memory>> load(List<Map<String, dynamic>> rows, {ContentCipher? as}) async {
      if (as != null) repo = build(as);
      backend.respond((_) => FakeBackend.ok(rows));
      return repo.getMemories('c1');
    }

    test('a sealed memory is opened and an older readable one is still shown', () async {
      final sealed = await row('m1', content: {'title': 'Our first doodle', 'emoji': '🎨'}, path: 'c1/m1.enc');
      final legacy = await row('m2', path: 'c1/old.png');

      final memories = await load([sealed, legacy]);

      expect(memories.map((m) => m.title), ['Our first doodle', 'Old readable title']);
      expect(memories.first.thumbnailEmoji, '🎨');
      expect(memories.first.thumbnailUrl, 'c1/m1.enc', reason: 'the Storage path; the picture is loaded through loadImage');
    });

    test('a memory this phone cannot open shows as locked instead of disappearing', () async {
      final foreign = await row('m1', content: {'title': 'Secret', 'emoji': '🤫'}, by: await readyCipher());
      final memories = await load([foreign]);
      expect(memories, hasLength(1));
      expect(memories.single.title, isNot('Secret'));
    });

    test('without the couple key sealed memories show as locked', () async {
      final sealed = await row('m1', content: {'title': 'Secret', 'emoji': '🤫'});
      final memories = await load([sealed], as: notReadyCipher());
      expect(memories.single.title, isNot('Secret'));
    });

    test('a memory copied onto another row does not open', () async {
      final sealed = await row('m1', content: {'title': 'Secret', 'emoji': '🤫'});
      final memories = await load([{...sealed, 'id': 'm-other'}]);
      expect(memories.single.title, isNot('Secret'));
    });
  });

  group('loadImage', () {
    Memory memory(String id, String? path, {String coupleId = 'c1'}) => Memory(
          id: id,
          coupleId: coupleId,
          type: MemoryType.canvas,
          thumbnailEmoji: '🎨',
          title: 't',
          createdAt: DateTime(2026),
          createdByUserId: 'u2',
          thumbnailUrl: path,
        );

    Future<Uint8List> sealedPicture(String id, {ContentCipher? by}) =>
        (by ?? cipher).sealBytes(png, coupleId: 'c1', table: 'memories', rowId: id, field: 'image');

    test('a sealed picture is downloaded and opened', () async {
      final sealed = await sealedPicture('m1');
      backend.respond((_) => http200(sealed));

      expect(await repo.loadImage(memory('m1', 'c1/m1.enc')), png);
    });

    test('an older readable picture is returned as it is', () async {
      backend.respond((_) => http200(png));
      expect(await repo.loadImage(memory('m1', 'c1/old.png')), png);
    });

    test('the second request is served from memory', () async {
      final sealed = await sealedPicture('m1');
      backend.respond((_) => http200(sealed));
      final m = memory('m1', 'c1/m1.enc');

      await repo.loadImage(m);
      final before = backend.requests.length;
      expect(await repo.loadImage(m), png);

      expect(backend.requests.length, before);
    });

    test('a picture sealed for another memory does not open, so the emoji is shown', () async {
      final sealed = await sealedPicture('m-other');
      backend.respond((_) => http200(sealed));
      expect(await repo.loadImage(memory('m1', 'c1/m1.enc')), isNull);
    });

    test('without the couple key, or a failed download, there is no picture', () async {
      final sealed = await sealedPicture('m1');
      backend.respond((_) => http200(sealed));
      expect(await build(notReadyCipher()).loadImage(memory('m1', 'c1/m1.enc')), isNull);

      backend.respond((_) => FakeBackend.error('404', 'not found', status: 404));
      expect(await repo.loadImage(memory('m2', 'c1/m2.enc')), isNull);
    });

    test('a memory with no picture has nothing to load', () async {
      expect(await repo.loadImage(memory('m1', null)), isNull);
      expect(backend.requests, isEmpty);
    });
  });
}
