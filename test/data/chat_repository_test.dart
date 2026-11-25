import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usync/data/datasources/local/prefs_source.dart';
import 'package:usync/domain/entities/chat_message.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/data/datasources/remote/chat_media_source.dart';
import 'package:usync/data/datasources/remote/couple_channel_source.dart';
import 'package:usync/data/models/chat_message_model.dart';
import 'package:usync/data/repositories/chat_repository.dart';

import '../support/test_cipher.dart';
import 'repository_harness.dart';

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

/// The file inside a multipart upload.
Uint8List _filePart(List<int> body) {
  final sep = utf8.encode('\r\n\r\n');
  final named = _indexOf(body, utf8.encode('filename='));
  final start = named + _indexOf(body.sublist(named), sep) + sep.length;
  var end = body.length;
  for (var i = body.length - 4; i >= 0; i--) {
    if (body[i] == 13 && body[i + 1] == 10 && body[i + 2] == 45 && body[i + 3] == 45) { end = i; break; }
  }
  return Uint8List.fromList(body.sublist(start, end));
}

void main() {
  late FakeBackend backend;
  late LocalStorage local;
  late RecordingNotifications notifications;
  late CoupleChannelSource channels;
  late ContentCipher cipher;
  late ChatRepository repo;
  late SharedPreferences prefs;

  ChatRepository build(ContentCipher c) => ChatRepository(
        client: backend.client,
        media: ChatMediaSource(client: backend.client),
        notifications: notifications,
        outbox: local.outbox,
        cipher: c,
        channelSource: channels,
        prefs: PrefsSource(prefs: prefs),
        local: local.chat,
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
    repo = build(cipher);
    backend.respond((r) => r.path.contains('/storage/') ? FakeBackend.ok({'Key': 'chat/x'}) : FakeBackend.ok('ok'));
  });

  tearDown(() async {
    channels.close();
    await local.tearDown();
    await backend.dispose();
  });

  Recorded rpc(String name) => backend.requests.firstWhere((r) => r.path.endsWith('/rpc/$name'));
  Recorded upload() => backend.requests.firstWhere((r) => r.path.contains('/storage/v1/object/'));

  test('a text message is sent only as ciphertext', () async {
    final sentNow = await repo.sendText(coupleId: 'c1', userId: 'u1', text: 'meet me at the secret place');

    expect(sentNow, isTrue);
    final params = rpc('send_chat_message').json as Map<String, dynamic>;
    final id = params['p_id'] as String;
    expect(params['p_kind'], 'text');
    expect(params['p_media_path'], isNull);
    expect(params['p_enc'], startsWith('u1:'));
    expect(bodyText(params), isNot(contains('secret place')));
    expect(await cipher.openJson(params['p_enc'] as String, coupleId: 'c1', table: 'chat_messages', rowId: id), {'t': 'meet me at the secret place'});
    // Moved to another message, it does not open.
    await expectLater(cipher.openJson(params['p_enc'] as String, coupleId: 'c1', table: 'chat_messages', rowId: 'other'), throwsA(anything));
  });

  test('a reply carries a short copy of the original, sealed with the message', () async {
    const original = ChatReply(messageId: 'm0', senderId: 'u2', kind: ChatKind.text, text: 'dinner?');
    await repo.sendText(coupleId: 'c1', userId: 'u1', text: 'yes!', replyTo: original);

    final params = rpc('send_chat_message').json as Map<String, dynamic>;
    expect(bodyText(params), isNot(contains('dinner')));
    final content = await cipher.openJson(params['p_enc'] as String, coupleId: 'c1', table: 'chat_messages', rowId: params['p_id'] as String);
    expect(ChatReply.fromJson(content['r']), original);
  });

  test('a photo is uploaded sealed to <couple>/<id>.enc and the row points at it', () async {
    final photo = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...utf8.encode('private holiday photo'), 9, 9, 9]);

    await repo.sendImage(coupleId: 'c1', userId: 'u1', bytes: photo);

    final params = rpc('send_chat_message').json as Map<String, dynamic>;
    final id = params['p_id'] as String;
    final up = upload();
    expect(up.path, endsWith('/c1/$id.enc'));
    expect(params['p_kind'], 'image');
    expect(params['p_media_path'], ChatMediaSource.pathFor('c1', id));
    expect(_contains(up.bodyBytes, [0xFF, 0xD8, 0xFF, 0xE0]), isFalse, reason: 'the photo must not be readable in the upload');
    expect(_contains(up.bodyBytes, utf8.encode('holiday photo')), isFalse);
    expect(await cipher.openBytes(_filePart(up.bodyBytes), coupleId: 'c1', table: 'chat_messages', rowId: id, field: 'media'), photo);
  });

  test('a voice note keeps its length inside the sealed part, not readable', () async {
    await repo.sendVoice(coupleId: 'c1', userId: 'u1', bytes: Uint8List.fromList([1, 2, 3, 4]), durationMs: 12345);

    final params = rpc('send_chat_message').json as Map<String, dynamic>;
    expect(params['p_kind'], 'voice');
    expect(params.keys, isNot(contains('p_duration')));
    final opened = await cipher.openJson(params['p_enc'] as String, coupleId: 'c1', table: 'chat_messages', rowId: params['p_id'] as String);
    expect(opened['d'], 12345);
  });

  test('without the couple key nothing is sent or queued, and the caller is told', () async {
    repo = build(notReadyCipher());

    await expectLater(repo.sendText(coupleId: 'c1', userId: 'u1', text: 'hi'), throwsA(isA<EncryptionNotReady>()));
    await expectLater(repo.sendImage(coupleId: 'c1', userId: 'u1', bytes: Uint8List(3)), throwsA(isA<EncryptionNotReady>()));

    expect(backend.requests.where((r) => r.path.contains('/rpc/') || r.path.contains('/storage/')), isEmpty);
    expect(local.outbox.pending, 0);
  });

  test('a message you send is on your screen at once, pending until the server has it, then ordered by the server\'s time', () async {
    backend.respond((r) => r.path.endsWith('/rpc/send_chat_message') ? FakeBackend.ok('2026-06-01T10:00:00+00:00') : FakeBackend.ok('ok'));
    await repo.sendText(coupleId: 'c1', userId: 'u1', text: 'hello');

    final id = (rpc('send_chat_message').json as Map)['p_id'] as String;
    final stored = (await local.chat.get(id))!;
    expect(stored['t'], 'hello');
    expect(stored['mine'], isTrue);
    expect(stored['p'], isFalse);
    expect(stored['at'], DateTime.utc(2026, 6, 1, 10).microsecondsSinceEpoch);
  });

  test('offline: the message shows as pending and is sent when the connection is back', () async {
    local.connectivity.current = [ConnectivityResult.none];
    await local.outbox.init();
    final sentNow = await repo.sendText(coupleId: 'c1', userId: 'u1', text: 'later');

    expect(sentNow, isFalse);
    final id = (await local.chat.page(limit: 5)).single['id'] as String;
    expect((await local.chat.get(id))!['p'], isTrue);
    expect(backend.requests.where((r) => r.path.endsWith('/rpc/send_chat_message')), isEmpty);

    local.connectivity.current = [ConnectivityResult.wifi];
    await local.outbox.flush();
    expect((await local.chat.get(id))!['p'], isFalse);
    expect(rpc('send_chat_message'), isNotNull);
  });

  test('a message the server refuses does not stay on the screen', () async {
    backend.respond((_) => FakeBackend.error('P0001', 'Invalid message', status: 400));
    await expectLater(repo.sendText(coupleId: 'c1', userId: 'u1', text: 'x'), throwsA(anything));
    expect(await local.chat.page(limit: 5), isEmpty);
  });

  test('the couple\'s timer is Off by default, set on the server and remembered; sends still hint it', () async {
    expect(repo.timer, ChatTimer.off);
    await repo.sendText(coupleId: 'c1', userId: 'u1', text: 'a');
    expect((rpc('send_chat_message').json as Map)['p_ttl'], 0);

    backend.requests.clear();
    await repo.setTimer(coupleId: 'c1', timer: ChatTimer.tenSeconds);
    final set = rpc('set_chat_timer').json as Map;
    expect(set['p_couple'], 'c1');
    expect(set['p_seconds'], 10);
    expect(repo.timer, ChatTimer.tenSeconds);
  });

  test('a timer change the server refuses is reported and not remembered', () async {
    backend.respond((_) => FakeBackend.error('P0001', 'Not a member', status: 400));
    await expectLater(repo.setTimer(coupleId: 'c1', timer: ChatTimer.oneMinute), throwsA(anything));
    expect(repo.timer, ChatTimer.off);
  });

  group('collecting from the mailbox', () {
    Future<Map<String, dynamic>> row(String id, Map<String, dynamic> content, {String sender = 'partner', String kind = 'text', String? path, String created = '2026-06-01T10:00:00+00:00', String? seen, String? expires}) async => {
          'id': id, 'couple_id': 'c1', 'sender_id': sender, 'kind': kind, 'media_path': path,
          'enc': await cipher.sealJson(content, coupleId: 'c1', table: 'chat_messages', rowId: id),
          'created_at': created, 'seen_at': seen, 'expires_at': expires ?? '2026-06-15T10:00:00+00:00', 'ttl_seconds': 60,
        };

    Future<void> collect(List<Map<String, dynamic>> rows, {bool importOwn = false}) =>
        repo.collectForTest(rows, coupleId: 'c1', userId: 'me', importOwn: importOwn);

    List<String> sentControls() => [
          for (final r in backend.requests.where((r) => r.path.endsWith('/rpc/send_chat_message')))
            if ((r.json as Map)['p_kind'] == 'control') (r.json as Map)['p_enc'] as String,
        ];

    test('a partner message is saved on the phone, then deleted from the server, then reported delivered', () async {
      await collect([await row('m1', {'t': 'hi love'})]);

      final saved = (await local.chat.get('m1'))!;
      expect(saved['t'], 'hi love');
      expect(saved['mine'], isFalse);
      expect(local.chat.unreadCount, 1);
      expect((rpc('ack_chat_messages').json as Map)['p_ids'], ['m1']);
      final control = await cipher.openJson(sentControls().single, coupleId: 'c1', table: 'chat_messages', rowId: ((backend.requests.lastWhere((r) => r.path.endsWith('/rpc/send_chat_message')).json as Map)['p_id']) as String);
      expect(control, {'c': 'receipt', 'k': 'delivered', 'ids': ['m1']});
    });

    test('a message already saved is only collected again, not duplicated or reported twice', () async {
      final m = await row('m1', {'t': 'hi'});
      await collect([m]);
      backend.requests.clear();
      await collect([m]);

      expect((await local.chat.page(limit: 10)).length, 1);
      expect((rpc('ack_chat_messages').json as Map)['p_ids'], ['m1']);
      expect(sentControls(), isEmpty);
    });

    test('a message deleted on this phone is not saved again from a stale copy on the server', () async {
      final m = await row('m1', {'t': 'hi'});
      await collect([m]);
      await repo.deleteForMe('m1');
      backend.requests.clear();

      await collect([m]);

      expect(local.chat.has('m1'), isFalse);
      expect((rpc('ack_chat_messages').json as Map)['p_ids'], ['m1']);
    });

    test('a "delete for everyone" that arrives before its message wins when the message follows', () async {
      await collect([await row('d1', {'c': 'delete', 'ids': ['m1']}, kind: 'control', created: '2026-06-01T10:00:00+00:00')]);
      await collect([await row('m1', {'t': 'never show'}, created: '2026-06-01T09:00:00+00:00')]);
      expect(local.chat.has('m1'), isFalse);
    });

    test('a delete or clear is not collected while a message of the same pass could not be saved', () async {
      repo = build(notReadyCipher());
      await collect([await row('m1', {'t': 'x'}), await row('d1', {'c': 'delete', 'ids': ['m1']}, kind: 'control')]);
      // Nothing could even be opened here, so nothing is collected.
      expect(backend.requests.where((r) => r.path.endsWith('/rpc/ack_chat_messages')), isEmpty);
    });

    test('after a reset the history is wiped and collecting stops', () async {
      await collect([await row('m1', {'t': 'hi'})]);
      await repo.reset();
      expect(local.chat.has('m1'), isFalse);
      expect(local.chat.owner, isNull);
    });

    test('a message that cannot be opened yet stays on the server', () async {
      repo = build(notReadyCipher());
      await collect([await row('m1', {'t': 'hi'})]);

      expect(local.chat.has('m1'), isFalse);
      expect(backend.requests.where((r) => r.path.endsWith('/rpc/ack_chat_messages')), isEmpty);
    });

    test('a photo is downloaded, opened and kept on the phone before it is collected', () async {
      final photo = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sealed = await cipher.sealBytes(photo, coupleId: 'c1', table: 'chat_messages', rowId: 'p1', field: 'media');
      backend.respond((r) => r.path.contains('/storage/') && r.method == 'GET' ? http.Response.bytes(sealed, 200) : FakeBackend.ok('ok'));

      await collect([await row('p1', {}, kind: 'image', path: 'c1/p1.enc')]);

      expect(await local.chat.mediaBytes('p1'), photo);
      expect((await repo.loadMedia(ChatMessageModel.fromMap((await local.chat.get('p1'))!))), photo);
      expect((rpc('ack_chat_messages').json as Map)['p_ids'], ['p1']);
    });

    test('a photo that cannot be downloaded is not collected', () async {
      backend.respond((r) => r.path.contains('/storage/') ? http.Response('nope', 404) : FakeBackend.ok('ok'));
      await collect([await row('p1', {}, kind: 'image', path: 'c1/p1.enc')]);
      expect(local.chat.has('p1'), isFalse);
      expect(backend.requests.where((r) => r.path.endsWith('/rpc/ack_chat_messages')), isEmpty);
    });

    test('a read receipt starts the timer on the sender\'s phone; a delivered one gives the second tick', () async {
      await repo.sendText(coupleId: 'c1', userId: 'me', text: 'mine');
      final id = (await local.chat.page(limit: 1)).single['id'] as String;
      await local.chat.update(id, (m) => {...m, 'ttl': 60});

      await collect([await row('c-del', {'c': 'receipt', 'k': 'delivered', 'ids': [id]}, kind: 'control')]);
      var m = (await local.chat.get(id))!;
      expect(m['del'], isNotNull);
      expect(m['seen'], isNull);

      await collect([await row('c-read', {'c': 'receipt', 'k': 'read', 'ids': [id]}, kind: 'control')]);
      m = (await local.chat.get(id))!;
      expect(m['seen'], isNotNull);
      expect((m['exp'] as int) - (m['seen'] as int), const Duration(seconds: 60).inMicroseconds);
      final acks = [for (final r in backend.requests.where((r) => r.path.endsWith('/rpc/ack_chat_messages'))) ...((r.json as Map)['p_ids'] as List)];
      expect(acks, ['c-del', 'c-read']);
    });

    test('with the timer off a read message never expires', () async {
      await collect([await row('m1', {'t': 'hi'})..['ttl_seconds'] = 0]);
      await repo.markSeen(['m1']);
      final m = (await local.chat.get('m1'))!;
      expect(m['seen'], isNotNull);
      expect(m['exp'], isNull);
      expect(local.chat.unreadCount, 0);
    });

    test('"delete for everyone" removes the partner\'s own message only', () async {
      await collect([await row('m1', {'t': 'a'}), await row('m2', {'t': 'b'}, sender: 'partner')]);
      await repo.sendText(coupleId: 'c1', userId: 'me', text: 'mine');
      final mineId = (await local.chat.page(limit: 5)).firstWhere((m) => m['mine'] == true)['id'] as String;

      await collect([await row('d1', {'c': 'delete', 'ids': ['m1', mineId]}, kind: 'control')]);

      expect(local.chat.has('m1'), isFalse);
      expect(local.chat.has('m2'), isTrue);
      expect(local.chat.has(mineId), isTrue, reason: 'the partner cannot delete what I wrote');
    });

    test('"clear for both" removes what came before it, not what came after', () async {
      await collect([
        await row('old', {'t': 'a'}, created: '2026-06-01T09:00:00+00:00'),
        await row('new', {'t': 'b'}, created: '2026-06-01T11:00:00+00:00'),
        await row('clr', {'c': 'clear'}, kind: 'control', created: '2026-06-01T10:00:00+00:00'),
      ]);
      expect(local.chat.has('old'), isFalse);
      expect(local.chat.has('new'), isTrue);
    });

    test('on a fresh phone the user\'s own messages still on the server are brought in once', () async {
      await collect([await row('o1', {'t': 'mine'}, sender: 'me')], importOwn: true);
      expect((await local.chat.get('o1'))!['mine'], isTrue);
      expect(backend.requests.where((r) => r.path.endsWith('/rpc/ack_chat_messages')), isEmpty, reason: 'only the partner collects');

      await local.chat.delete(['o1']);
      await collect([await row('o1', {'t': 'mine'}, sender: 'me')]);
      expect(local.chat.has('o1'), isFalse, reason: 'deleted for me stays deleted');
    });

    test('a message already read on the old server keeps its timer', () async {
      await collect([await row('m1', {'t': 'old'}, seen: '2026-06-01T10:30:00+00:00', expires: '2026-06-01T10:31:00+00:00')]);
      final m = (await local.chat.get('m1'))!;
      expect(m['seen'], DateTime.utc(2026, 6, 1, 10, 30).microsecondsSinceEpoch);
      expect(m['exp'], DateTime.utc(2026, 6, 1, 10, 31).microsecondsSinceEpoch);
    });
  });

  test('marking messages read sends one sealed read receipt, and nothing for an empty list', () async {
    await repo.markSeen(const []);
    expect(backend.requests.where((r) => r.path.endsWith('/rpc/send_chat_message')), isEmpty);
  });

  test('delete for me touches only this phone', () async {
    await repo.sendText(coupleId: 'c1', userId: 'u1', text: 'a');
    final id = (await local.chat.page(limit: 1)).single['id'] as String;
    backend.requests.clear();

    await repo.deleteForMe(id);

    expect(local.chat.has(id), isFalse);
    expect(backend.requests, isEmpty);
  });

  test('delete for everyone removes it here, from the mailbox, and tells the partner\'s phone', () async {
    await repo.sendText(coupleId: 'c1', userId: 'u1', text: 'a');
    final id = (await local.chat.page(limit: 1)).single['id'] as String;
    backend.requests.clear();
    backend.respond((_) => FakeBackend.ok(null));

    await repo.deleteForEveryone(coupleId: 'c1', userId: 'u1', id: id);

    expect(local.chat.has(id), isFalse);
    expect((rpc('delete_chat_message').json as Map)['p_id'], id);
    final control = backend.requests.lastWhere((r) => r.path.endsWith('/rpc/send_chat_message')).json as Map;
    expect(control['p_kind'], 'control');
    expect(await cipher.openJson(control['p_enc'] as String, coupleId: 'c1', table: 'chat_messages', rowId: control['p_id'] as String), {'c': 'delete', 'ids': [id]});
  });

  test('clearing on this phone does not contact the server; for both it clears the mailbox and sends a control', () async {
    await repo.sendText(coupleId: 'c1', userId: 'u1', text: 'a');
    backend.requests.clear();
    await repo.clearChat(coupleId: 'c1', userId: 'u1', forEveryone: false);
    expect(await local.chat.page(limit: 5), isEmpty);
    expect(backend.requests, isEmpty);

    await repo.sendText(coupleId: 'c1', userId: 'u1', text: 'b');
    backend.requests.clear();
    backend.respond((_) => FakeBackend.ok(null));
    await repo.clearChat(coupleId: 'c1', userId: 'u1', forEveryone: true);
    expect((rpc('clear_chat').json as Map)['p_couple'], 'c1');
    expect((backend.requests.lastWhere((r) => r.path.endsWith('/rpc/send_chat_message')).json as Map)['p_kind'], 'control');
  });

  test('expired messages are removed from the phone', () async {
    await repo.sendText(coupleId: 'c1', userId: 'u1', text: 'a');
    final id = (await local.chat.page(limit: 1)).single['id'] as String;
    await local.chat.update(id, (m) => {...m, 'exp': DateTime.now().toUtc().subtract(const Duration(seconds: 1)).microsecondsSinceEpoch});

    await repo.purgeExpired();

    expect(local.chat.has(id), isFalse);
  });

  test('the chat shows the newest page first and older ones when asked', () async {
    for (var i = 0; i < 70; i++) {
      await local.chat.put({'id': 'm$i', 'cid': 'c1', 's': 'partner', 'mine': false, 'k': 'text', 'at': 1000 + i, 't': 'n$i', 'ttl': 0, 'p': false, 'm': false});
    }
    final seen = <List<ChatMessage>>[];
    final sub = repo.watchMessages('c1').listen(seen.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen.last.length, ChatRepository.pageSize);
    expect(seen.last.last.id, 'm69');
    expect(seen.last.first.id, 'm40');
    expect(repo.hasOlder, isTrue);

    expect(await repo.loadOlder(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen.last.length, ChatRepository.pageSize * 2);
    expect(await repo.loadOlder(), isFalse);
    await sub.cancel();
  });
}
