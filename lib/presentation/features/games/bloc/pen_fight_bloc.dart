import 'dart:async';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/game_session.dart';
import '../../../../domain/games/pen_fight.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_game_repository.dart';
import '../../../../domain/repositories/i_pen_fight_repository.dart';

sealed class PenFightEvent {}

class PenFightOpened extends PenFightEvent {
  PenFightOpened({required this.coupleId, required this.userId});
  final String coupleId, userId;
}

class PenFightStarted extends PenFightEvent {
  PenFightStarted([this.difficulty = PenDifficulty.normal]);
  final PenDifficulty difficulty;
}

/// The user let go of their pen: [dx], [dy] is the direction to flick, [power] is 0..1.
class PenFlicked extends PenFightEvent {
  PenFlicked(this.dx, this.dy, this.power);
  final double dx, dy, power;
}

/// Time passed on the screen (sent by its ticker); the bloc turns it into fixed simulation steps.
class PenTicked extends PenFightEvent {
  PenTicked(this.delta);
  final Duration delta;
}

/// Starts the next round after one was decided.
class PenNextRound extends PenFightEvent {}

class PenFightEnded extends PenFightEvent {}

class _SessionChanged extends PenFightEvent {
  _SessionChanged(this.session);
  final GameSession? session;
}

class _PartnerPresence extends PenFightEvent {
  _PartnerPresence(this.here);
  final bool here;
}

class _SendFailed extends PenFightEvent {}

class _MessageArrived extends PenFightEvent {
  _MessageArrived(this.message);
  final PenMessage message;
}

/// What the screen needs to show the two players.
class PenPlayers extends Equatable {
  const PenPlayers({this.ownEmoji = '🙂', this.partnerEmoji = '🌙', this.partnerName = 'Your partner'});
  final String ownEmoji, partnerEmoji, partnerName;

  @override
  List<Object?> get props => [ownEmoji, partnerEmoji, partnerName];
}

class _PlayersLoaded extends PenFightEvent {
  _PlayersLoaded(this.players, this.partnerId);
  final PenPlayers players;
  final String? partnerId;
}

class PenFightState extends Equatable {
  const PenFightState({
    this.players = const PenPlayers(),
    this.loading = true,
    this.session,
    this.busy = false,
    this.error,
    this.partnerHere = false,
    this.world = const PenWorld(own: PenBody(x: 0.5, y: 1.05, angle: -pi / 2), other: PenBody(x: 0.5, y: 0.35, angle: pi / 2)),
    this.difficulty = PenDifficulty.normal,
    this.turnUserId,
    this.myScore = 0,
    this.partnerScore = 0,
    this.round = 1,
    this.moving = false,
    this.roundOutcome = PenOutcome.none,
  });

  final PenPlayers   players;
  final bool         loading;
  final GameSession? session;
  final bool         busy;
  final String?      error;
  /// Whether the partner has the game open too (they said so over the channel).
  final bool         partnerHere;
  /// The pens, seen from this phone: yours at the bottom.
  final PenWorld     world;
  final String?      turnUserId;
  /// The level of this game (stored in the session, so both partners play the same).
  final PenDifficulty difficulty;
  final int          myScore, partnerScore, round;
  /// A flick is on its way (its motion is still being played, or the result is awaited).
  final bool         moving;
  /// Set once a round is decided (a pen fell); [PenOutcome.none] while play goes on.
  final PenOutcome   roundOutcome;

  bool get roundOver => roundOutcome != PenOutcome.none;

  PenFightState copyWith({
    PenPlayers? players, bool? loading, GameSession? session, bool clearSession = false, bool? busy, String? error,
    bool? partnerHere, PenWorld? world, PenDifficulty? difficulty, String? turnUserId, int? myScore, int? partnerScore, int? round,
    bool? moving, PenOutcome? roundOutcome,
  }) =>
      PenFightState(
        players:      players      ?? this.players,
        loading:      loading      ?? this.loading,
        session:      clearSession ? null : (session ?? this.session),
        busy:         busy         ?? this.busy,
        error:        error,
        partnerHere:  partnerHere  ?? this.partnerHere,
        world:        world        ?? this.world,
        difficulty:   difficulty   ?? this.difficulty,
        turnUserId:   turnUserId   ?? this.turnUserId,
        myScore:      myScore      ?? this.myScore,
        partnerScore: partnerScore ?? this.partnerScore,
        round:        round        ?? this.round,
        moving:       moving       ?? this.moving,
        roundOutcome: roundOutcome ?? this.roundOutcome,
      );

  @override
  List<Object?> get props => [
        players, loading, session, busy, error, partnerHere, world, difficulty, turnUserId,
        myScore, partnerScore, round, moving, roundOutcome,
      ];
}

class PenFightBloc extends Bloc<PenFightEvent, PenFightState> {
  PenFightBloc({
    required this.gameRepository,
    required this.penRepository,
    required this.authRepository,
    required this.coupleRepository,
  }) : super(const PenFightState()) {
    on<PenFightOpened>(_onOpened);
    on<_PlayersLoaded>((e, emit) {
      if (e.partnerId != null) _partnerId = e.partnerId!;
      emit(state.copyWith(players: e.players));
    });
    on<_SessionChanged>(_onSessionChanged);
    on<_PartnerPresence>((e, emit) {
      if (e.here != state.partnerHere) emit(state.copyWith(partnerHere: e.here));
    });
    on<_SendFailed>((_, emit) => emit(state.copyWith(error: 'Your move did not reach your partner. Check your connection.')));
    on<_MessageArrived>(_onMessage);
    on<PenFightStarted>(_onStarted);
    on<PenFlicked>(_onFlicked);
    on<PenTicked>(_onTicked);
    on<PenNextRound>(_onNextRound);
    on<PenFightEnded>(_onEnded);
  }

  final IGameRepository     gameRepository;
  final IPenFightRepository penRepository;
  final IAuthRepository     authRepository;
  final ICoupleRepository   coupleRepository;

  /// How long a phone waits for the flicker's final positions before it trusts its own result.
  static const _settleWait = Duration(seconds: 3);
  static const _stepMs     = PenFight.stepSeconds * 1000;

  String _coupleId = '', _userId = '', _partnerId = '';
  /// Who flicked the flick that is being played.
  String? _flicker;
  int _seq = 0, _lastPartnerSeq = 0;
  double _accMs = 0, _waitedMs = 0;
  PenWorld? _authoritative;
  StreamSubscription<List<GameSession>>? _sessions;
  StreamSubscription<PenMessage>?        _messages;
  StreamSubscription<bool>?              _presence;

  Future<void> _onOpened(PenFightOpened e, Emitter<PenFightState> emit) async {
    _coupleId = e.coupleId; _userId = e.userId;
    await _sessions?.cancel();
    await _messages?.cancel();
    await _presence?.cancel();
    unawaited(_loadPlayers());
    _sessions = gameRepository.watchSessions(_coupleId).listen(
      (all) {
        if (isClosed) return;
        final mine = all.where((s) => s.type == GameType.penFight).toList();
        add(_SessionChanged(mine.where((s) => s.isActive).firstOrNull ?? mine.firstOrNull));
      },
      onError: (_) {},
    );
    _messages = penRepository.watch(_coupleId).listen(
      (m) { if (!isClosed && m.from != _userId) add(_MessageArrived(m)); },
      onError: (_) {},
    );
    // Presence is the main way the phones find each other: announce this screen and watch for the partner's.
    gameRepository.enterGame(coupleId: _coupleId, userId: _userId, type: GameType.penFight).catchError((_) {});
    _presence = penRepository.watchPartnerHere(coupleId: _coupleId, userId: _userId).listen(
      (here) { if (!isClosed) add(_PartnerPresence(here)); },
      onError: (_) {},
    );
    // Also say hello over the channel (the partner answers "here"), in case Presence is slow.
    _send(PenMessage(type: PenMessageType.hello, from: _userId));
  }

  /// The avatars are only decoration: when they cannot be loaded the defaults stay.
  Future<void> _loadPlayers() async {
    try {
      final me      = await authRepository.getCurrentUser();
      final couple  = await coupleRepository.getCouple(_coupleId);
      final partnerId = couple.partnerIdFor(_userId);
      final partner = await authRepository.getUserById(partnerId);
      if (isClosed) return;
      add(_PlayersLoaded(
        PenPlayers(
          ownEmoji:     me?.avatarEmoji ?? '🙂',
          partnerEmoji: partner?.avatarEmoji ?? '🌙',
          partnerName:  partner?.username ?? 'Your partner',
        ),
        partnerId,
      ));
    } catch (_) {}
  }

  void _log(String text) {
    if (kDebugMode) debugPrint('[pen] $text');
  }

  void _send(PenMessage m) {
    _log('send ${m.type.name} seq=${m.seq}');
    penRepository.send(coupleId: _coupleId, message: m).catchError((Object e) {
      _log('send ${m.type.name} FAILED: ${e.runtimeType}');
      // A lost flick would leave the partner waiting for ever, so say so.
      if (!isClosed && (m.type == PenMessageType.flick || m.type == PenMessageType.settled)) add(_SendFailed());
    });
  }

  void _onSessionChanged(_SessionChanged e, Emitter<PenFightState> emit) {
    final fresh = e.session?.id != state.session?.id;
    if (fresh) _resetGame();
    final level = PenDifficulty.fromKey(e.session?.state['difficulty']);
    emit(PenFightState(
      difficulty: level,
      players: state.players,
      loading: false,
      session: e.session,
      busy: state.busy,
      partnerHere: state.partnerHere,
      // A new game: the pens in their places, the one who started it goes first.
      world: fresh ? PenWorld.start(level) : state.world.copyWith(difficulty: level),
      turnUserId: fresh ? e.session?.createdBy : state.turnUserId,
      myScore: fresh ? 0 : state.myScore,
      partnerScore: fresh ? 0 : state.partnerScore,
      round: fresh ? 1 : state.round,
      moving: fresh ? false : state.moving,
      roundOutcome: fresh ? PenOutcome.none : state.roundOutcome,
    ));
  }

  void _resetGame() {
    _flicker = null; _seq = 0; _lastPartnerSeq = 0; _accMs = 0; _waitedMs = 0; _authoritative = null;
  }

  Future<void> _onStarted(PenFightStarted e, Emitter<PenFightState> emit) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true));
    try {
      await gameRepository.start(coupleId: _coupleId, userId: _userId, type: GameType.penFight, state: {'difficulty': e.difficulty.key});
      emit(state.copyWith(busy: false));
    } catch (_) {
      emit(state.copyWith(busy: false, error: 'Could not start the game. Check your connection.'));
    }
  }

  bool get _canFlick {
    final s = state.session;
    return s != null && s.isActive && state.partnerHere && state.turnUserId == _userId &&
        !state.moving && !state.roundOver;
  }

  void _onFlicked(PenFlicked e, Emitter<PenFightState> emit) {
    if (!_canFlick) return;
    final world = state.world.flicked(e.dx, e.dy, e.power);
    if (!world.own.moving) return; // too gentle to count
    _seq++;
    _flicker = _userId; _accMs = 0; _waitedMs = 0; _authoritative = null;
    emit(state.copyWith(world: world, moving: true));
    _send(PenMessage(type: PenMessageType.flick, from: _userId, seq: _seq, world: world, round: state.round));
  }

  void _onTicked(PenTicked e, Emitter<PenFightState> emit) {
    if (!state.moving) return;
    var world = state.world;
    final ms = e.delta.inMicroseconds / 1000;
    if (!world.settled) {
      // A long pause (the app was in the background) must not fast-forward the whole flick.
      _accMs = min(_accMs + ms, 100);
      while (_accMs >= _stepMs && !world.settled) {
        world = world.step();
        _accMs -= _stepMs;
      }
      emit(state.copyWith(world: world));
    }
    if (!world.settled) return;

    if (_flicker == _userId) {
      // This phone's flick: its result is the one that counts, so tell the partner.
      _send(PenMessage(type: PenMessageType.settled, from: _userId, seq: _seq, world: world, round: state.round));
      _finishRound(world, emit);
    } else if (_authoritative != null) {
      _finishRound(_authoritative!, emit);
    } else {
      // Waiting for the flicker's final positions; if they never come, go with this phone's own result.
      _waitedMs += ms;
      if (_waitedMs >= _settleWait.inMilliseconds) _finishRound(world, emit);
    }
  }

  /// Ends the flick that was being played: scores a decided round, or passes the turn.
  void _finishRound(PenWorld result, Emitter<PenFightState> emit) {
    final still = result.copyWith(
      own:   result.own.copyWith(vx: 0, vy: 0),
      other: result.other.copyWith(vx: 0, vy: 0),
    );
    final outcome = still.outcome;
    var mine = state.myScore, theirs = state.partnerScore;
    // Whoever's pen fell starts the next round; otherwise the turn simply passes on.
    String? turn = _flicker == _userId ? _partnerId : _userId;
    switch (outcome) {
      case PenOutcome.ownWon:   mine++;   turn = _partnerId;
      case PenOutcome.otherWon: theirs++; turn = _userId;
      case PenOutcome.draw:
      case PenOutcome.none:     break;
    }
    _flicker = null; _authoritative = null; _waitedMs = 0; _accMs = 0;
    emit(state.copyWith(
      world: still, moving: false, roundOutcome: outcome,
      myScore: mine, partnerScore: theirs, turnUserId: turn,
    ));
  }

  void _onMessage(_MessageArrived e, Emitter<PenFightState> emit) {
    final m = e.message;
    _log('got ${m.type.name} seq=${m.seq} (moving=${state.moving}, roundOver=${state.roundOver}, active=${state.session?.isActive})');
    _partnerId = m.from;
    switch (m.type) {
      case PenMessageType.hello:
        _send(PenMessage(type: PenMessageType.here, from: _userId));
        if (!state.partnerHere) emit(state.copyWith(partnerHere: true));
      case PenMessageType.here:
        if (!state.partnerHere) emit(state.copyWith(partnerHere: true));
      case PenMessageType.bye:
        if (state.partnerHere) emit(state.copyWith(partnerHere: false));
      case PenMessageType.flick:
        final world = m.worldForReceiver?.copyWith(difficulty: state.difficulty);
        final s = state.session;
        if (world == null || s == null || !s.isActive || state.moving || state.roundOver || m.seq <= _lastPartnerSeq) return;
        _lastPartnerSeq = m.seq;
        _flicker = m.from; _accMs = 0; _waitedMs = 0; _authoritative = null;
        emit(state.copyWith(partnerHere: true, world: world, moving: true, turnUserId: m.from));
      case PenMessageType.settled:
        final world = m.worldForReceiver?.copyWith(difficulty: state.difficulty);
        if (world == null || m.seq < _lastPartnerSeq) return;
        if (state.moving && _flicker == m.from) {
          _authoritative = world;
          // Already stopped here: nothing more to play, so finish now.
          if (state.world.settled) _finishRound(world, emit);
        } else if (!state.moving && !state.roundOver && m.seq > _lastPartnerSeq) {
          // The flick itself never arrived: take the result as it is.
          _lastPartnerSeq = m.seq;
          _flicker = m.from;
          _finishRound(world, emit);
        }
      case PenMessageType.next:
        if (state.roundOver && m.round > state.round) _startRound(m.round, emit);
    }
  }

  void _onNextRound(PenNextRound _, Emitter<PenFightState> emit) {
    if (!state.roundOver) return;
    final round = state.round + 1;
    _send(PenMessage(type: PenMessageType.next, from: _userId, round: round));
    _startRound(round, emit);
  }

  void _startRound(int round, Emitter<PenFightState> emit) {
    _flicker = null; _authoritative = null; _waitedMs = 0; _accMs = 0;
    emit(state.copyWith(world: PenWorld.start(state.difficulty), round: round, roundOutcome: PenOutcome.none, moving: false));
  }

  Future<void> _onEnded(PenFightEnded _, Emitter<PenFightState> emit) async {
    final s = state.session;
    if (s == null || !s.isActive) return;
    try {
      await gameRepository.finish(s.id);
    } catch (_) {
      emit(state.copyWith(error: 'Could not end the game. Check your connection.'));
    }
  }

  @override
  Future<void> close() async {
    if (_coupleId.isNotEmpty) {
      _send(PenMessage(type: PenMessageType.bye, from: _userId));
      gameRepository.leaveGame(coupleId: _coupleId, userId: _userId).catchError((_) {});
    }
    await _presence?.cancel();
    await _sessions?.cancel();
    await _messages?.cancel();
    return super.close();
  }
}
