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
  bool? clearedForEveryone;
  bool clearFails = false;

  @override
  Future<void> clearChat({required String coupleId, required String userId, required bool forEveryone}) async {
    if (clearFails) throw Exception('offline');
    cleared++;
    clearedForEveryone = forEveryone;
  }

  final deleted = <String>[];
  final deletedForEveryone = <String>[];
  bool deleteFails = false;

  @override
  Future<void> deleteForMe(String id) async {
    if (deleteFails) throw Exception('disk');
    deleted.add(id);
  }

  @override
  Future<void> deleteForEveryone({required String coupleId, required String userId, required String id}) async {
    if (deleteFails) throw Exception('offline');
    deletedForEveryone.add(id);
  }

  var inboxStarts = 0;
  var purges = 0;
  var olderRequests = 0;
  @override
  bool hasOlder = false;

  @override
  Future<void> reset() async {}

  @override
  Future<void> startInbox({required String coupleId, required String userId}) async => inboxStarts++;

  @override
  Future<void> purgeExpired() async => purges++;

  @override
  Future<bool> loadOlder() async {
    olderRequests++;
    return hasOlder;
  }

  @override
  Future<void> enterChat({required String coupleId, required String userId}) async => presence.add('enter');

  @override
  Future<void> leaveChat({required String coupleId, required String userId}) async => presence.add('leave');
}

ChatMessage _msg(String id, {String sender = 'partner', DateTime? seenAt, DateTime? expiresAt, bool locked = false}) => ChatMessage(
      id: id, coupleId: 'c', senderId: sender, kind: ChatKind.text, text: 'hi $id',
      createdAt: DateTime(2026, 1, 1), expiresAt: expiresAt, seenAt: seenAt, locked: locked,
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

  test('opening the chat with no user or couple yet does nothing (sign-in not restored)', () async {
    final other = _FakeChat();
    final b = ChatBloc(chatRepository: other, clock: () => now, tickEvery: const Duration(milliseconds: 20));
    addTearDown(b.close);
    b.add(ChatOpened(coupleId: '', userId: ''));
    await pump();
    expect(other.inboxStarts, 0);
    expect(b.state.loading, isTrue);
  });

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
    expect(bloc.state.timer, ChatTimer.off);
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

  test('opening the chat starts collecting and drops expired messages', () async {
    expect(repo.inboxStarts, 1);
    expect(repo.purges, 1);
  });

  group('deleting', () {
    test('delete for me removes it from this phone only', () async {
      bloc.add(ChatMessageDeleted('2'));
      await pump();
      expect(repo.deleted, ['2']);
      expect(repo.deletedForEveryone, isEmpty);
    });

    test('delete for everyone is passed on', () async {
      bloc.add(ChatMessageDeleted('2', forEveryone: true));
      await pump();
      expect(repo.deletedForEveryone, ['2']);
      expect(repo.deleted, isEmpty);
    });

    test('if the partner\'s phone cannot be told, the user gets a notice', () async {
      repo.deleteFails = true;
      bloc.add(ChatMessageDeleted('1', forEveryone: true));
      await pump();
      expect(bloc.state.notice, contains('Could not delete'));
    });

    test('a message deleted or removed shows up as gone when the list changes', () async {
      repo.changes.add([_msg('1'), _msg('2')]);
      await pump();
      repo.changes.add([_msg('2')]);
      await pump();
      expect(bloc.state.messages.map((m) => m.id), ['2']);
    });
  });

  group('clearing', () {
    test('clearing on this phone and on both are told apart', () async {
      bloc.add(ChatCleared());
      await pump();
      expect(repo.cleared, 1);
      expect(repo.clearedForEveryone, isFalse);

      bloc.add(ChatCleared(forEveryone: true));
      await pump();
      expect(repo.cleared, 2);
      expect(repo.clearedForEveryone, isTrue);
    });

    test('a clear for both that cannot reach the partner gives a notice', () async {
      repo.clearFails = true;
      bloc.add(ChatCleared(forEveryone: true));
      await pump();
      expect(bloc.state.notice, contains('Could not clear'));
    });
  });

  group('older messages', () {
    test('asks for an older page only when there is one', () async {
      bloc.add(ChatOlderRequested());
      await pump();
      expect(repo.olderRequests, 0);

      repo.hasOlder = true;
      repo.changes.add([_msg('1')]);
      await pump();
      expect(bloc.state.hasOlder, isTrue);
      bloc.add(ChatOlderRequested());
      await pump();
      expect(repo.olderRequests, 1);
    });
  });

  group('shared timer', () {
    test('when the partner changes the timer it changes here too', () async {
      expect(bloc.state.timer, ChatTimer.off);
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
      expect(bloc.state.timer, ChatTimer.off);
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
      repo.timerChanges.add(ChatTimer.off);
      await pump();
      bloc.add(ChatTimerChanged(ChatTimer.oneMinute));
      await pump();
      repo.timerChanges.add(ChatTimer.oneMinute);
      await pump();
      expect(bloc.state.notices, hasLength(1));
    });

    test('choosing the timer that is already set adds nothing', () async {
      bloc.add(ChatTimerChanged(ChatTimer.off));
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
    ChatMessage media(String id, ChatKind kind, {String sender = 'partner', int ttl = 60}) => ChatMessage(
          id: id, coupleId: 'c', senderId: sender, kind: kind, mediaPath: 'c/$id.enc',
          createdAt: DateTime(2026, 1, 1), ttlSeconds: ttl,
        );

    test('a photo or voice note appearing on screen does not start its timer', () async {
      bloc.add(ChatVisibilityChanged(visible: true));
      repo.changes.add([media('p', ChatKind.image), media('v', ChatKind.voice), _msg('t')]);
      await pump();
      expect(repo.seen, [['t']], reason: 'only the text is marked seen by being on screen');
    });

    test('with the timer Off a photo is nothing to hide: being on screen counts as read, a voice note still waits', () async {
      bloc.add(ChatVisibilityChanged(visible: true));
      repo.changes.add([media('p', ChatKind.image, ttl: 0), media('v', ChatKind.voice, ttl: 0)]);
      await pump();
      expect(repo.seen, [['p']]);
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
