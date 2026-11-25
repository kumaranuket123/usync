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
  Future<void> setTimer({required String coupleId, required ChatTimer timer}) async {
    if (timerFails) throw Exception('offline');
    _timer = timer;
  }

  final timerChanges = StreamController<ChatTimer>.broadcast();
  bool timerFails = false;

  @override
  Stream<ChatTimer> watchTimer(String coupleId) => timerChanges.stream;

  @override
  Stream<List<ChatMessage>> watchMessages(String coupleId) => changes.stream;

  @override
  Future<bool> sendText({required String coupleId, required String userId, required String text, ChatReply? replyTo}) async {
    if (sendError != null) throw sendError!;
    texts.add(text);
    return delivered;
  }

  @override
  Future<bool> sendImage({required String coupleId, required String userId, required Uint8List bytes, ChatReply? replyTo}) async => delivered;

  @override
  Future<bool> sendVoice({required String coupleId, required String userId, required Uint8List bytes, required int durationMs, ChatReply? replyTo}) async => delivered;

  @override
  Future<void> markSeen(List<String> ids) async {
    if (seenFails) throw Exception('offline');
    seen.add(ids);
  }

  @override
  Future<Uint8List?> loadMedia(ChatMessage message) async => null;

  @override
  Stream<int> watchUnreadCount({required String coupleId, required String userId}) => const Stream.empty();

  int cleared = 0;
  final partnerClears = StreamController<void>.broadcast();
  bool clearFails = false;

  @override
  Future<void> clearChat({required String coupleId, required String userId}) async {
    if (clearFails) throw Exception('offline');
    cleared++;
  }

  @override
  Stream<void> watchCleared(String coupleId) => partnerClears.stream;

  final deleted = <String>[];
  final partnerDeletes = StreamController<String>.broadcast();
  bool deleteFails = false;

  @override
  Future<void> deleteMessage({required String coupleId, required String userId, required String id}) async {
    if (deleteFails) throw Exception('offline');
    deleted.add(id);
  }

  @override
  Stream<String> watchDeleted(String coupleId) => partnerDeletes.stream;

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

  group('deleting', () {
    test('a message I delete disappears at once and is deleted on the server', () async {
      repo.changes.add([_msg('1'), _msg('2', sender: 'me')]);
      await pump();
      bloc.add(ChatMessageDeleted('2'));
      await pump();
      expect(bloc.state.messages.map((m) => m.id), ['1']);
      expect(repo.deleted, ['2']);
    });

    test('I can delete my partner\'s message too', () async {
      repo.changes.add([_msg('1'), _msg('2', sender: 'me')]);
      await pump();
      bloc.add(ChatMessageDeleted('1'));
      await pump();
      expect(bloc.state.messages.map((m) => m.id), ['2']);
      expect(repo.deleted, ['1']);
    });

    test('a deleted message stays gone even if the table stream still lists it', () async {
      repo.changes.add([_msg('1')]);
      await pump();
      bloc.add(ChatMessageDeleted('1'));
      await pump();
      repo.changes.add([_msg('1'), _msg('2')]);
      await pump();
      expect(bloc.state.messages.map((m) => m.id), ['2']);
    });

    test('a message the partner deletes disappears from my screen', () async {
      repo.changes.add([_msg('1'), _msg('2')]);
      await pump();
      repo.partnerDeletes.add('1');
      await pump();
      expect(bloc.state.messages.map((m) => m.id), ['2']);
      expect(repo.deleted, isEmpty, reason: 'the partner already deleted it on the server');
    });

    test('if the server cannot be reached the message comes back, with a notice', () async {
      repo.deleteFails = true;
      repo.changes.add([_msg('1')]);
      await pump();
      bloc.add(ChatMessageDeleted('1'));
      await pump();
      expect(bloc.state.messages.map((m) => m.id), ['1']);
      expect(bloc.state.notice, contains('Could not delete'));
    });
  });

  group('clearing', () {
    test('clearing empties the chat at once and clears it on the server', () async {
      repo.changes.add([_msg('1'), _msg('2', sender: 'me')]);
      await pump();
      bloc.add(ChatCleared());
      await pump();
      expect(bloc.state.messages, isEmpty);
      expect(repo.cleared, 1);
    });

    test('messages sent after clearing show up as usual', () async {
      repo.changes.add([_msg('1')]);
      await pump();
      bloc.add(ChatCleared());
      await pump();
      repo.changes.add([_msg('1'), _msg('new', sender: 'me')]);
      await pump();
      expect(bloc.state.messages.map((m) => m.id), ['new']);
    });

    test('when the partner clears the chat it empties on my screen', () async {
      repo.changes.add([_msg('1'), _msg('2')]);
      await pump();
      repo.partnerClears.add(null);
      await pump();
      expect(bloc.state.messages, isEmpty);
      expect(repo.cleared, 0, reason: 'the partner already cleared it on the server');
    });

    test('if the server cannot be reached everything comes back, with a notice', () async {
      repo.clearFails = true;
      repo.changes.add([_msg('1'), _msg('2')]);
      await pump();
      bloc.add(ChatCleared());
      await pump();
      expect(bloc.state.messages.map((m) => m.id), ['1', '2']);
      expect(bloc.state.notice, contains('Could not clear'));
    });
  });

  group('shared timer', () {
    test('when the partner changes the timer it changes here too', () async {
      expect(bloc.state.timer, ChatTimer.oneDay);
      repo.timerChanges.add(ChatTimer.oneMinute);
      await pump();
      expect(bloc.state.timer, ChatTimer.oneMinute);
    });

    test('the timer the server has wins when the chat opens', () async {
      repo.timerChanges.add(ChatTimer.tenSeconds);
      await pump();
      expect(bloc.state.timer, ChatTimer.tenSeconds);
    });

    test('if the server cannot be reached the old timer comes back, with a notice', () async {
      repo.timerFails = true;
      bloc.add(ChatTimerChanged(ChatTimer.oneMinute));
      await pump();
      expect(bloc.state.timer, ChatTimer.oneDay);
      expect(bloc.state.notice, contains('Could not change the timer'));
    });

    test('messages keep showing while the timer changes', () async {
      repo.changes.add([_msg('1')]);
      await pump();
      repo.timerChanges.add(ChatTimer.fiveMinutes);
      await pump();
      expect(bloc.state.messages.map((m) => m.id), ['1']);
    });
  });

  group('timer lines', () {
    test('changing the timer adds a line after the newest message', () async {
      repo.changes.add([_msg('1')]);
      await pump();
      bloc.add(ChatTimerChanged(ChatTimer.oneMinute));
      await pump();
      final n = bloc.state.notices.single;
      expect(n.byMe, isTrue);
      expect(n.timer, ChatTimer.oneMinute);
      expect(n.at.isAfter(DateTime(2026, 1, 1)), isTrue, reason: 'after the message');
    });

    test('a line is placed after the newest message even if this phone\'s clock is behind', () async {
      final newest = DateTime(2030, 1, 1);
      repo.changes.add([ChatMessage(id: 'n', coupleId: 'c', senderId: 'partner', kind: ChatKind.text, text: 'x', createdAt: newest, expiresAt: DateTime(2031))]);
      await pump();
      bloc.add(ChatTimerChanged(ChatTimer.oneMinute));
      await pump();
      expect(bloc.state.notices.single.at.isAfter(newest), isTrue);
    });

    test('the partner\'s change adds a line too, but the first value from the server does not', () async {
      repo.timerChanges.add(ChatTimer.fiveMinutes); // what the server had when the chat opened
      await pump();
      expect(bloc.state.notices, isEmpty);
      repo.timerChanges.add(ChatTimer.oneMinute);
      await pump();
      expect(bloc.state.notices.single.byMe, isFalse);
      expect(bloc.state.notices.single.timer, ChatTimer.oneMinute);
    });

    test('my own change coming back from the server does not add a second line', () async {
      repo.timerChanges.add(ChatTimer.oneDay);
      await pump();
      bloc.add(ChatTimerChanged(ChatTimer.oneMinute));
      await pump();
      repo.timerChanges.add(ChatTimer.oneMinute);
      await pump();
      expect(bloc.state.notices, hasLength(1));
    });

    test('choosing the timer that is already set adds nothing', () async {
      bloc.add(ChatTimerChanged(ChatTimer.oneDay));
      await pump();
      expect(bloc.state.notices, isEmpty);
    });

    test('a change that fails leaves no line behind', () async {
      repo.timerFails = true;
      bloc.add(ChatTimerChanged(ChatTimer.oneMinute));
      await pump();
      expect(bloc.state.notices, isEmpty);
    });

    test('clearing the chat clears the lines too', () async {
      bloc.add(ChatTimerChanged(ChatTimer.oneMinute));
      await pump();
      bloc.add(ChatCleared());
      await pump();
      expect(bloc.state.notices, isEmpty);
    });
  });

  group('photos and voice notes', () {
    ChatMessage media(String id, ChatKind kind, {String sender = 'partner'}) => ChatMessage(
          id: id, coupleId: 'c', senderId: sender, kind: kind, mediaPath: 'c/$id.enc',
          createdAt: DateTime(2026, 1, 1), expiresAt: DateTime(2030),
        );

    test('a photo or voice note appearing on screen does not start its timer', () async {
      bloc.add(ChatVisibilityChanged(visible: true));
      repo.changes.add([media('p', ChatKind.image), media('v', ChatKind.voice), _msg('t')]);
      await pump();
      expect(repo.seen, [['t']], reason: 'only the text is marked seen by being on screen');
    });

    test('revealing a photo starts its timer, once', () async {
      bloc.add(ChatVisibilityChanged(visible: true));
      repo.changes.add([media('p', ChatKind.image)]);
      await pump();
      bloc.add(ChatMediaRevealed('p'));
      bloc.add(ChatMediaRevealed('p'));
      await pump();
      expect(repo.seen, [['p']]);
    });

    test('a reveal that could not be sent is tried again on the next tap', () async {
      repo.seenFails = true;
      bloc.add(ChatMediaRevealed('p'));
      await pump();
      expect(repo.seen, isEmpty);
      repo.seenFails = false;
      bloc.add(ChatMediaRevealed('p'));
      await pump();
      expect(repo.seen, [['p']]);
    });

    test('an unrevealed photo is still there however long the chat stays open', () async {
      bloc.add(ChatVisibilityChanged(visible: true));
      repo.changes.add([media('p', ChatKind.image)]);
      await pump(80);
      expect(bloc.state.messages.map((m) => m.id), ['p']);
    });
  });
}
