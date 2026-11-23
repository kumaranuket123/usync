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

/// The chat is in front of the user (or not): only then are incoming messages counted as seen.
class ChatVisibilityChanged extends ChatEvent {
  ChatVisibilityChanged({required this.visible});
  final bool visible;
}

/// The user chose how long their messages live after they are seen.
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

class ChatState extends Equatable {
  const ChatState({
    this.loading = true,
    this.messages = const [],
    this.now,
    this.userId = '',
    this.timer = ChatTimer.defaultTimer,
    this.notice,
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

  @override
  List<Object?> get props => [loading, messages, now, userId, timer, notice];
}

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({required this.chatRepository, DateTime Function()? clock, this.tickEvery = const Duration(seconds: 1)})
      : _clock = clock ?? DateTime.now,
        super(const ChatState()) {
    on<ChatOpened>(_onOpened);
    on<_MessagesChanged>(_onMessages);
    on<_Tick>(_onTick);
    on<ChatVisibilityChanged>(_onVisibility);
    on<ChatTimerChanged>((e, emit) async {
      await chatRepository.setTimer(e.timer);
      emit(ChatState(loading: state.loading, messages: state.messages, now: state.now, userId: _userId, timer: e.timer));
    });
    on<ChatTextSent>((e, emit) => _send(emit, () => chatRepository.sendText(coupleId: _coupleId, userId: _userId, text: e.text.trim()), skip: e.text.trim().isEmpty));
    on<ChatImageSent>((e, emit) => _send(emit, () => chatRepository.sendImage(coupleId: _coupleId, userId: _userId, bytes: e.bytes)));
    on<ChatVoiceSent>((e, emit) => _send(emit, () => chatRepository.sendVoice(coupleId: _coupleId, userId: _userId, bytes: e.bytes, durationMs: e.durationMs)));
  }

  final IChatRepository  chatRepository;
  final DateTime Function() _clock;
  final Duration         tickEvery;
  String _coupleId = '', _userId = '';
  bool _visible = false;
  List<ChatMessage> _all = const [];
  /// Ids already reported as seen, so each is sent once.
  final _reported = <String>{};
  StreamSubscription<List<ChatMessage>>? _sub;
  Timer? _timer;

  Future<void> _onOpened(ChatOpened e, Emitter<ChatState> emit) async {
    _coupleId = e.coupleId; _userId = e.userId;
    emit(ChatState(userId: _userId, now: _clock(), timer: chatRepository.timer));
    await _sub?.cancel();
    _sub = chatRepository.watchMessages(_coupleId).listen(
      (m) { if (!isClosed) add(_MessagesChanged(m)); },
      onError: (_) {},
    );
    _timer?.cancel();
    _timer = Timer.periodic(tickEvery, (_) { if (!isClosed) add(_Tick()); });
  }

  List<ChatMessage> _alive(DateTime now) => [for (final m in _all) if (!m.isExpired(now)) m];

  void _onMessages(_MessagesChanged e, Emitter<ChatState> emit) {
    _all = e.messages;
    final now = _clock();
    emit(ChatState(loading: false, messages: _alive(now), now: now, userId: _userId, timer: chatRepository.timer));
    _reportSeen();
  }

  void _onTick(_Tick _, Emitter<ChatState> emit) {
    if (state.loading) return;
    final now = _clock();
    final alive = _alive(now);
    // Nothing expired: no need to redraw.
    if (alive.length == state.messages.length) return;
    emit(ChatState(loading: false, messages: alive, now: now, userId: _userId, timer: chatRepository.timer));
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

  /// Starts the 5-minute timer of the partner's messages that have just been seen. A failure is not
  /// remembered, so the next change or return to the screen tries again.
  void _reportSeen() {
    if (!_visible) return;
    final now = _clock();
    final ids = [
      for (final m in _all)
        if (!m.isMine(_userId) && !m.isSeen && !m.locked && !m.isExpired(now) && !_reported.contains(m.id)) m.id,
    ];
    if (ids.isEmpty) return;
    _reported.addAll(ids);
    chatRepository.markSeen(ids).catchError((_) => _reported.removeAll(ids));
  }

  Future<void> _send(Emitter<ChatState> emit, Future<bool> Function() send, {bool skip = false}) async {
    if (skip) return;
    try {
      final delivered = await send();
      if (!delivered) {
        emit(ChatState(loading: false, messages: state.messages, now: state.now, userId: _userId, timer: state.timer, notice: 'No connection: it will be sent when you are back online.'));
      }
    } on EncryptionNotReady catch (e) {
      emit(ChatState(loading: false, messages: state.messages, now: state.now, userId: _userId, timer: state.timer, notice: e.message));
    } catch (_) {
      emit(ChatState(loading: false, messages: state.messages, now: state.now, userId: _userId, timer: state.timer, notice: 'Could not send. Try again.'));
    }
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    // The screen closing: events added now may never run, and the partner must not keep thinking we are here.
    if (_visible && _coupleId.isNotEmpty) chatRepository.leaveChat(coupleId: _coupleId, userId: _userId).catchError((_) {});
    _visible = false;
    await _sub?.cancel();
    return super.close();
  }
}
