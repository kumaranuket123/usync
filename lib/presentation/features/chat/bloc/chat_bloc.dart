import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/crypto/content_cipher.dart';
import '../../../../domain/entities/chat_message.dart';
import '../../../../domain/repositories/i_chat_repository.dart';

sealed class ChatEvent {}

class ChatOpened extends ChatEvent {
  ChatOpened({required this.coupleId, required this.userId});
  final String coupleId, userId;
}

class _MessagesChanged extends ChatEvent {
  _MessagesChanged(this.messages);
  final List<ChatMessage> messages;
}

class _Tick extends ChatEvent {}

/// The couple's timer, as the server has it (loaded, or changed by the partner).
class _TimerFromServer extends ChatEvent {
  _TimerFromServer(this.timer);
  final ChatTimer timer;
}

/// The user deletes a message: from this phone, or (their own messages) from both phones.
class ChatMessageDeleted extends ChatEvent {
  ChatMessageDeleted(this.id, {this.forEveryone = false});
  final String id;
  final bool   forEveryone;
}

/// The user scrolled to the top: show an older page.
class ChatOlderRequested extends ChatEvent {}

/// The user revealed a partner's photo or voice note (opened the photo, played the voice note): from now
/// on the timer runs for it. Until then it stays.
class ChatMediaRevealed extends ChatEvent {
  ChatMediaRevealed(this.id);
  final String id;
}

/// The user clears the whole chat: on this phone, or on both.
class ChatCleared extends ChatEvent {
  ChatCleared({this.forEveryone = false});
  final bool forEveryone;
}

/// The chat is in front of the user (or not): only then are incoming messages counted as seen.
class ChatVisibilityChanged extends ChatEvent {
  ChatVisibilityChanged({required this.visible});
  final bool visible;
}

/// The user chose how long messages live after they are seen (for both partners, from now on).
class ChatTimerChanged extends ChatEvent {
  ChatTimerChanged(this.timer);
  final ChatTimer timer;
}

class ChatTextSent extends ChatEvent {
  ChatTextSent(this.text);
  final String text;
}

class ChatImageSent extends ChatEvent {
  ChatImageSent(this.bytes);
  final Uint8List bytes;
}

class ChatVoiceSent extends ChatEvent {
  ChatVoiceSent({required this.bytes, required this.durationMs});
  final Uint8List bytes;
  final int       durationMs;
}

/// The user starts replying to a message (dragged it).
class ChatReplyStarted extends ChatEvent {
  ChatReplyStarted(this.message);
  final ChatMessage message;
}

/// The user dropped the reply they were writing.
class ChatReplyCancelled extends ChatEvent {}

class ChatState extends Equatable {
  const ChatState({
    this.loading = true,
    this.messages = const [],
    this.now,
    this.userId = '',
    this.timer = ChatTimer.defaultTimer,
    this.notice,
    this.notices = const [],
    this.replyingTo,
    this.hasOlder = false,
  });

  final bool              loading;
  /// Messages that still exist, oldest first (expired ones are already left out).
  final List<ChatMessage> messages;
  final DateTime?         now;
  final String            userId;
  /// How long the messages this user sends live after they are seen.
  final ChatTimer         timer;
  /// A one-off message for the user (a failed send); cleared by the next state.
  final String?           notice;
  /// "Timer changed" lines to show among the messages, oldest first.
  final List<ChatTimerNotice> notices;
  /// The message the user is writing a reply to.
  final ChatMessage? replyingTo;
  /// Older messages than those shown exist on this phone.
  final bool hasOlder;

  @override
  List<Object?> get props => [loading, messages, now, userId, timer, notice, notices, replyingTo, hasOlder];
}

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({required this.chatRepository, DateTime Function()? clock, this.tickEvery = const Duration(seconds: 1)})
      : _clock = clock ?? DateTime.now,
        super(const ChatState()) {
    on<ChatOpened>(_onOpened);
    on<_MessagesChanged>(_onMessages);
    on<_Tick>(_onTick);
    on<ChatVisibilityChanged>(_onVisibility);
    on<ChatMessageDeleted>(_onDelete);
    on<ChatOlderRequested>(_onOlder);
    on<ChatMediaRevealed>((e, _) => _markSeen([e.id]));
    on<ChatCleared>(_onClear);
    on<ChatReplyStarted>((e, emit) { _replyTo = e.message; _show(emit); });
    on<ChatReplyCancelled>((_, emit) { _replyTo = null; _show(emit); });
    on<ChatTimerChanged>(_onTimerChanged);
    on<_TimerFromServer>((e, emit) {
      // The first value is just what the server has; a later different one is the partner's change.
      if (_timerKnown && e.timer != _chatTimer) _addNotice(e.timer, byMe: false);
      _timerKnown = true;
      _chatTimer = e.timer;
      _show(emit);
    });
    on<ChatTextSent>((e, emit) => _send(emit, () => chatRepository.sendText(coupleId: _coupleId, userId: _userId, text: e.text.trim(), replyTo: _reply()), skip: e.text.trim().isEmpty));
    on<ChatImageSent>((e, emit) => _send(emit, () => chatRepository.sendImage(coupleId: _coupleId, userId: _userId, bytes: e.bytes, replyTo: _reply())));
    on<ChatVoiceSent>((e, emit) => _send(emit, () => chatRepository.sendVoice(coupleId: _coupleId, userId: _userId, bytes: e.bytes, durationMs: e.durationMs, replyTo: _reply())));
  }

  final IChatRepository  chatRepository;
  final DateTime Function() _clock;
  final Duration         tickEvery;
  String _coupleId = '', _userId = '';
  bool _visible = false;
  ChatTimer _chatTimer = ChatTimer.defaultTimer;
  /// "Timer changed" lines of this visit to the chat.
  var _notices = <ChatTimerNotice>[];
  /// The timer the server has was loaded: from then on a different value is a change worth a line in the chat.
  bool _timerKnown = false;
  List<ChatMessage> _all = const [];
  /// The message the next one sent answers.
  ChatMessage? _replyTo;
  ChatReply? _reply() => _replyTo == null ? null : ChatReply.of(_replyTo!);
  /// Ids already reported as seen, so each is sent once.
  final _reported = <String>{};
  StreamSubscription<List<ChatMessage>>? _sub;
  StreamSubscription<ChatTimer>?         _timerSub;
  bool _loadingOlder = false;
  Timer? _timer;

  Future<void> _onOpened(ChatOpened e, Emitter<ChatState> emit) async {
    // Sign-in not restored yet: wait for the screen to open the chat again with real ids.
    if (e.coupleId.isEmpty || e.userId.isEmpty) return;
    _coupleId = e.coupleId; _userId = e.userId;
    _chatTimer = chatRepository.timer;
    emit(ChatState(userId: _userId, now: _clock(), timer: _chatTimer));
    // Collects what the partner sent (Home does too; this is a no-op then) and drops what has expired.
    try {
      await chatRepository.startInbox(coupleId: _coupleId, userId: _userId);
      await chatRepository.purgeExpired();
    } catch (_) {}
    await _sub?.cancel();
    _sub = chatRepository.watchMessages(_coupleId).listen(
      (m) { if (!isClosed) add(_MessagesChanged(m)); },
      onError: (_) {},
    );
    await _timerSub?.cancel();
    _timerSub = chatRepository.watchTimer(_coupleId).listen(
      (t) { if (!isClosed) add(_TimerFromServer(t)); },
      onError: (_) {},
    );
    _timer?.cancel();
    _timer = Timer.periodic(tickEvery, (_) { if (!isClosed) add(_Tick()); });
  }

  List<ChatMessage> _alive(DateTime now) => [for (final m in _all) if (!m.isExpired(now)) m];

  void _onMessages(_MessagesChanged e, Emitter<ChatState> emit) {
    _all = e.messages;
    _show(emit);
    _reportSeen();
  }

  void _onTick(_Tick _, Emitter<ChatState> emit) {
    if (state.loading) return;
    final now = _clock();
    final alive = _alive(now);
    // Nothing expired: no need to redraw.
    if (alive.length == state.messages.length) return;
    // Their timer has run out: gone from the screen now, and from this phone's storage.
    chatRepository.purgeExpired().catchError((_) {});
    _show(emit);
  }

  void _show(Emitter<ChatState> emit, {String? notice}) {
    final now = _clock();
    emit(ChatState(
      loading: false, messages: _alive(now), now: now, userId: _userId, timer: _chatTimer, notices: _notices,
      replyingTo: _replyTo, hasOlder: chatRepository.hasOlder, notice: notice,
    ));
  }

  Future<void> _onOlder(ChatOlderRequested e, Emitter<ChatState> emit) async {
    if (_loadingOlder || !chatRepository.hasOlder) return;
    _loadingOlder = true;
    try {
      await chatRepository.loadOlder(); // the messages stream reports the longer list
    } finally {
      _loadingOlder = false;
    }
  }

  /// Puts a "timer changed" line after the newest message.
  void _addNotice(ChatTimer timer, {required bool byMe}) {
    var at = _clock();
    final last = _all.isEmpty ? null : _all.last.createdAt;
    if (last != null && !at.isAfter(last)) at = last.add(const Duration(milliseconds: 1));
    _notices = [..._notices, ChatTimerNotice(at: at, timer: timer, byMe: byMe)];
  }

  Future<void> _onTimerChanged(ChatTimerChanged e, Emitter<ChatState> emit) async {
    final before = _chatTimer;
    if (e.timer == before) return;
    _chatTimer = e.timer;
    _addNotice(e.timer, byMe: true);
    final added = _notices.last;
    _show(emit);
    try {
      await chatRepository.setTimer(coupleId: _coupleId, timer: e.timer);
    } catch (_) {
      _chatTimer = before;
      _notices = [for (final n in _notices) if (n != added) n];
      _show(emit, notice: 'Could not change the timer. Check your connection.');
    }
  }

  Future<void> _onClear(ChatCleared e, Emitter<ChatState> emit) async {
    _notices = const [];
    _show(emit);
    try {
      await chatRepository.clearChat(coupleId: _coupleId, userId: _userId, forEveryone: e.forEveryone);
    } catch (_) {
      _show(emit, notice: 'Could not clear the chat for your partner. Check your connection.');
    }
  }

  Future<void> _onDelete(ChatMessageDeleted e, Emitter<ChatState> emit) async {
    try {
      if (e.forEveryone) {
        await chatRepository.deleteForEveryone(coupleId: _coupleId, userId: _userId, id: e.id);
      } else {
        await chatRepository.deleteForMe(e.id);
      }
    } catch (_) {
      _show(emit, notice: e.forEveryone ? 'Could not delete the message for your partner. Check your connection.' : 'Could not delete the message.');
    }
  }

  void _onVisibility(ChatVisibilityChanged e, Emitter<ChatState> emit) {
    _visible = e.visible;
    // Tell the partner whether we are looking, so a message needs no push; a failure only costs one push.
    if (_coupleId.isNotEmpty && _userId.isNotEmpty) {
      final done = _visible
          ? chatRepository.enterChat(coupleId: _coupleId, userId: _userId)
          : chatRepository.leaveChat(coupleId: _coupleId, userId: _userId);
      done.catchError((_) {});
    }
    if (_visible) _reportSeen();
  }

  /// The decrypted photo or voice note of [message] (kept in memory only), or null.
  Future<Uint8List?> loadMedia(ChatMessage message) => chatRepository.loadMedia(message);

  /// Starts the timer of the partner's TEXT messages that have just been seen (and of photos when the timer is
  /// Off, since nothing is hidden then). Photos with a timer and voice notes are
  /// left out: their timer starts when the user reveals them ([ChatMediaRevealed]). A failure is not
  /// remembered, so the next change, return to the screen or tap tries again.
  void _reportSeen() {
    if (!_visible) return;
    final now = _clock();
    final ids = [
      for (final m in _all)
        if ((m.kind == ChatKind.text || (m.kind == ChatKind.image && m.ttlSeconds == 0)) && !m.isMine(_userId) && !m.isSeen && !m.locked && !m.isExpired(now) && !_reported.contains(m.id)) m.id,
    ];
    _markSeen(ids);
  }

  void _markSeen(List<String> ids) {
    final fresh = [for (final id in ids) if (_reported.add(id)) id];
    if (fresh.isEmpty) return;
    chatRepository.markSeen(fresh).catchError((_) => _reported.removeAll(fresh));
  }

  Future<void> _send(Emitter<ChatState> emit, Future<bool> Function() send, {bool skip = false}) async {
    if (skip) return;
    try {
      final sending = send(); // reads the reply now
      // The reply belongs to this message only.
      if (_replyTo != null) {
        _replyTo = null;
        _show(emit);
      }
      final delivered = await sending;
      if (!delivered) {
        _show(emit, notice: 'No connection: it will be sent when you are back online.');
      }
    } on EncryptionNotReady catch (e) {
      _show(emit, notice: e.message);
    } catch (_) {
      _show(emit, notice: 'Could not send. Try again.');
    }
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    // The screen closing: events added now may never run, and the partner must not keep thinking we are here.
    if (_visible && _coupleId.isNotEmpty) chatRepository.leaveChat(coupleId: _coupleId, userId: _userId).catchError((_) {});
    _visible = false;
    await _sub?.cancel();
    await _timerSub?.cancel();
    return super.close();
  }
}
