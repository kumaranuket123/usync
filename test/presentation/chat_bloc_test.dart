import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/domain/entities/chat_message.dart';
import 'package:usync/domain/repositories/i_chat_repository.dart';
import 'package:usync/presentation/features/chat/bloc/chat_bloc.dart';

class _FakeChat implements IChatRepository {
  final changes = StreamController<List<ChatMessage>>.broadcast();
  final texts = <String>[];
  final seen = <List<String>>[];
  final presence = <String>[];
  ChatTimer _timer = ChatTimer.defaultTimer;
  Object? sendError;
  bool delivered = true;
  bool seenFails = false;

  @override
  ChatTimer get timer => _timer;

  @override
  Future<void> setTimer(ChatTimer timer) async => _timer = timer;

  @override
  Stream<List<ChatMessage>> watchMessages(String coupleId) => changes.stream;

  @override
  Future<bool> sendText({required String coupleId, required String userId, required String text}) async {
    if (sendError != null) throw sendError!;
    texts.add(text);
    return delivered;
  }

  @override
  Future<bool> sendImage({required String coupleId, required String userId, required Uint8List bytes}) async => delivered;

  @override
  Future<bool> sendVoice({required String coupleId, required String userId, required Uint8List bytes, required int durationMs}) async => delivered;

  @override
  Future<void> markSeen(List<String> ids) async {
    if (seenFails) throw Exception('offline');
    seen.add(ids);
  }

  @override
  Future<Uint8List?> loadMedia(ChatMessage message) async => null;

  @override
  Future<void> enterChat({required String coupleId, required String userId}) async => presence.add('enter');

  @override
  Future<void> leaveChat({required String coupleId, required String userId}) async => presence.add('leave');
}

ChatMessage _msg(String id, {String sender = 'partner', DateTime? seenAt, DateTime? expiresAt, bool locked = false}) => ChatMessage(
      id: id, coupleId: 'c', senderId: sender, kind: ChatKind.text, text: 'hi $id',
      createdAt: DateTime(2026, 1, 1), expiresAt: expiresAt ?? DateTime(2030), seenAt: seenAt, locked: locked,
    );

void main() {
  late _FakeChat repo;
  late ChatBloc bloc;
  late DateTime now;

  setUp(() async {
    now = DateTime(2026, 6, 1, 12);
    repo = _FakeChat();
    bloc = ChatBloc(chatRepository: repo, clock: () => now, tickEvery: const Duration(milliseconds: 20));
    bloc.add(ChatOpened(coupleId: 'c', userId: 'me'));
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() => bloc.close());

  Future<void> pump([int ms = 10]) => Future<void>.delayed(Duration(milliseconds: ms));

  test('shows the messages that exist', () async {
    repo.changes.add([_msg('1'), _msg('2', sender: 'me')]);
    await pump();
    expect(bloc.state.loading, isFalse);
    expect(bloc.state.messages.map((m) => m.id), ['1', '2']);
  });

  test('leaves out a message whose time has passed, also when the clock moves on', () async {
    repo.changes.add([_msg('1', seenAt: now, expiresAt: now.add(const Duration(minutes: 5))), _msg('2')]);
    await pump();
    expect(bloc.state.messages.length, 2);

    now = now.add(const Duration(minutes: 5, seconds: 1));
    await pump(60);

    expect(bloc.state.messages.map((m) => m.id), ['2']);
  });

  test('reports the partner\'s messages as seen only while the chat is in front, once each', () async {
    repo.changes.add([_msg('1'), _msg('2', sender: 'me'), _msg('3', locked: true)]);
    await pump();
    expect(repo.seen, isEmpty, reason: 'not visible yet');

    bloc.add(ChatVisibilityChanged(visible: true));
    await pump();
    expect(repo.seen, [['1']], reason: 'only the partner\'s readable, unseen message');

    repo.changes.add([_msg('1'), _msg('2', sender: 'me'), _msg('4')]);
    await pump();
    expect(repo.seen, [['1'], ['4']], reason: 'the first one is not reported again');
  });

  test('does not report messages already seen, and tries again after a failure', () async {
    repo.seenFails = true;
    bloc.add(ChatVisibilityChanged(visible: true));
    repo.changes.add([_msg('1'), _msg('2', seenAt: now, expiresAt: now.add(const Duration(minutes: 5)))]);
    await pump();
    expect(repo.seen, isEmpty);

    repo.seenFails = false;
    repo.changes.add([_msg('1'), _msg('2', seenAt: now, expiresAt: now.add(const Duration(minutes: 5)))]);
    await pump();
    expect(repo.seen, [['1']]);
  });

  test('tells the partner when we are looking, and when we leave', () async {
    bloc.add(ChatVisibilityChanged(visible: true));
    await pump();
    bloc.add(ChatVisibilityChanged(visible: false));
    await pump();
    expect(repo.presence, ['enter', 'leave']);
  });

  test('starts with the saved timer and changes it when the user chooses', () async {
    expect(bloc.state.timer, ChatTimer.oneDay);
    bloc.add(ChatTimerChanged(ChatTimer.oneMinute));
    await pump();
    expect(repo.timer, ChatTimer.oneMinute);
    expect(bloc.state.timer, ChatTimer.oneMinute);
  });

  test('sends trimmed text and ignores an empty one', () async {
    bloc.add(ChatTextSent('  hello  '));
    bloc.add(ChatTextSent('   '));
    await pump();
    expect(repo.texts, ['hello']);
  });

  test('says so when the key is missing, when offline, and when sending fails', () async {
    repo.sendError = const EncryptionNotReady();
    bloc.add(ChatTextSent('a'));
    await pump();
    expect(bloc.state.notice, contains('securing your connection'));

    repo.sendError = null;
    repo.delivered = false;
    bloc.add(ChatTextSent('b'));
    await pump();
    expect(bloc.state.notice, contains('back online'));

    repo.sendError = Exception('boom');
    bloc.add(ChatTextSent('c'));
    await pump();
    expect(bloc.state.notice, 'Could not send. Try again.');
  });

  test('leaves the chat announcement when it is closed while visible', () async {
    bloc.add(ChatVisibilityChanged(visible: true));
    await pump();
    await bloc.close();
    expect(repo.presence.last, 'leave');
  });
}
