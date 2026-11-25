import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usync/data/datasources/local/prefs_source.dart';
import 'package:usync/domain/entities/chat_message.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/data/datasources/remote/chat_media_source.dart';
import 'package:usync/data/datasources/remote/couple_channel_source.dart';
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

  test('the couple\'s timer is set on the server and remembered; sends still hint it', () async {
    expect(repo.timer, ChatTimer.oneDay);
    await repo.sendText(coupleId: 'c1', userId: 'u1', text: 'a');
    expect((rpc('send_chat_message').json as Map)['p_ttl'], 86400);

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
    expect(repo.timer, ChatTimer.oneDay);
  });

  test('marking messages seen calls the RPC with their ids, and nothing for an empty list', () async {
    await repo.markSeen(const []);
    expect(backend.requests.where((r) => r.path.endsWith('/rpc/mark_chat_seen')), isEmpty);

    await repo.markSeen(const ['a', 'b']);
    expect((rpc('mark_chat_seen').json as Map)['p_ids'], ['a', 'b']);
  });

  test('deleting a message calls the RPC with its id', () async {
    backend.respond((_) => FakeBackend.ok(null));
    await repo.deleteMessage(coupleId: 'c1', userId: 'u1', id: 'm1');
    expect((rpc('delete_chat_message').json as Map)['p_id'], 'm1');
  });

  test('a delete the server refuses is reported to the caller', () async {
    backend.respond((_) => FakeBackend.error('P0001', 'Not a member', status: 400));
    await expectLater(repo.deleteMessage(coupleId: 'c1', userId: 'u1', id: 'm1'), throwsA(anything));
  });

  test('clearing the chat calls the RPC with the couple', () async {
    backend.respond((_) => FakeBackend.ok(null));
    await repo.clearChat(coupleId: 'c1', userId: 'u1');
    expect((rpc('clear_chat').json as Map)['p_couple'], 'c1');
  });

  test('a clear the server refuses is reported to the caller', () async {
    backend.respond((_) => FakeBackend.error('P0001', 'Not a member', status: 400));
    await expectLater(repo.clearChat(coupleId: 'c1', userId: 'u1'), throwsA(anything));
  });

  group('unread count', () {
    final now = DateTime(2026, 6, 1, 12);
    Map<String, dynamic> row(String id, {String sender = 'partner', String? seen, DateTime? expires}) => {
          'id': id, 'sender_id': sender, 'seen_at': seen, 'expires_at': (expires ?? DateTime(2030)).toIso8601String(),
        };
    int count(List<Map<String, dynamic>> rows, {Set<String> gone = const {}}) =>
        ChatRepository.countUnread(rows, userId: 'me', gone: gone, now: now);

    test('counts only the partner\'s messages that nobody has seen', () {
      expect(count([row('1'), row('2'), row('3', seen: '2026-06-01T11:00:00Z'), row('4', sender: 'me')]), 2);
    });

    test('leaves out expired messages and ones the partner deleted', () {
      expect(count([row('1', expires: DateTime(2026, 6, 1, 11)), row('2'), row('3')], gone: {'3'}), 1);
    });

    test('is zero for an empty chat', () {
      expect(count(const []), 0);
    });
  });
}
