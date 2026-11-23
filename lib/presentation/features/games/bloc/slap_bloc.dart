import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/game_session.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../../domain/repositories/i_game_repository.dart';
import '../../../../domain/repositories/i_slap_repository.dart';

sealed class SlapEvent {}

class SlapOpened extends SlapEvent {
  SlapOpened({required this.coupleId, required this.userId});
  final String coupleId, userId;
}

class _SessionChanged extends SlapEvent {
  _SessionChanged(this.session);
  final GameSession? session;
}

class _SlapArrived extends SlapEvent {}

class SlapStarted extends SlapEvent {}

/// This user slapped their partner.
class SlapSent extends SlapEvent {}

class SlapEnded extends SlapEvent {}

/// What the screen needs to show the two players.
class SlapPlayers extends Equatable {
  const SlapPlayers({this.ownEmoji = '🙂', this.partnerEmoji = '🌙', this.partnerName = 'Your partner'});
  final String ownEmoji, partnerEmoji, partnerName;

  @override
  List<Object?> get props => [ownEmoji, partnerEmoji, partnerName];
}

class _PlayersLoaded extends SlapEvent {
  _PlayersLoaded(this.players);
  final SlapPlayers players;
}

class SlapState extends Equatable {
  const SlapState({
    this.players = const SlapPlayers(),
    this.loading = true,
    this.session,
    this.busy = false,
    this.error,
    this.given = 0,
    this.received = 0,
  });

  final SlapPlayers  players;
  final bool         loading;
  final GameSession? session;
  final bool         busy;
  final String?      error;
  /// Slaps this user gave / took since the game was opened (counted on the phone, not stored).
  final int          given, received;

  SlapState copyWith({SlapPlayers? players, bool? loading, GameSession? session, bool clearSession = false, bool? busy, String? error, int? given, int? received}) =>
      SlapState(
        players:  players  ?? this.players,
        loading:  loading  ?? this.loading,
        session:  clearSession ? null : (session ?? this.session),
        busy:     busy     ?? this.busy,
        error:    error,
        given:    given    ?? this.given,
        received: received ?? this.received,
      );

  @override
  List<Object?> get props => [players, loading, session, busy, error, given, received];
}

class SlapBloc extends Bloc<SlapEvent, SlapState> {
  SlapBloc({
    required this.gameRepository,
    required this.slapRepository,
    required this.authRepository,
    required this.coupleRepository,
    this.minGap = const Duration(milliseconds: 150)})
      : super(const SlapState()) {
    on<SlapOpened>(_onOpened);
    on<_PlayersLoaded>((e, emit) => emit(state.copyWith(players: e.players)));
    on<_SessionChanged>(_onSessionChanged);
    on<_SlapArrived>((_, emit) => emit(state.copyWith(received: state.received + 1)));
    on<SlapStarted>(_onStarted);
    on<SlapSent>(_onSent);
    on<SlapEnded>(_onEnded);
  }

  final IGameRepository gameRepository;
  final ISlapRepository slapRepository;
  final IAuthRepository authRepository;
  final ICoupleRepository coupleRepository;
  /// Shortest time between two slaps, so holding the button down cannot flood the channel.
  final Duration        minGap;
  String _coupleId = '', _userId = '';
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<List<GameSession>>? _sessions;
  StreamSubscription<String>?            _slaps;

  Future<void> _onOpened(SlapOpened e, Emitter<SlapState> emit) async {
    _coupleId = e.coupleId; _userId = e.userId;
    await _sessions?.cancel();
    await _slaps?.cancel();
    unawaited(_loadPlayers());
    _sessions = gameRepository.watchSessions(_coupleId).listen(
      (all) {
        if (isClosed) return;
        final mine = all.where((s) => s.type == GameType.slap).toList();
        add(_SessionChanged(mine.where((s) => s.isActive).firstOrNull ?? mine.firstOrNull));
      },
      onError: (_) {},
    );
    _slaps = slapRepository.watchSlaps(_coupleId).listen(
      (from) { if (!isClosed && from != _userId) add(_SlapArrived()); },
      onError: (_) {},
    );
  }

  /// The avatars are only decoration: when they cannot be loaded the defaults stay.
  Future<void> _loadPlayers() async {
    try {
      final me      = await authRepository.getCurrentUser();
      final couple  = await coupleRepository.getCouple(_coupleId);
      final partner = await authRepository.getUserById(couple.partnerIdFor(_userId));
      if (isClosed) return;
      add(_PlayersLoaded(SlapPlayers(
        ownEmoji:     me?.avatarEmoji ?? '🙂',
        partnerEmoji: partner?.avatarEmoji ?? '🌙',
        partnerName:  partner?.username ?? 'Your partner',
      )));
    } catch (_) {}
  }

  void _onSessionChanged(_SessionChanged e, Emitter<SlapState> emit) {
    // A new game starts the count again.
    final fresh = e.session?.id != state.session?.id;
    emit(state.copyWith(
      loading: false, session: e.session, clearSession: e.session == null,
      given: fresh ? 0 : null, received: fresh ? 0 : null,
    ));
  }

  Future<void> _onStarted(SlapStarted _, Emitter<SlapState> emit) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true));
    try {
      await gameRepository.start(coupleId: _coupleId, userId: _userId, type: GameType.slap, state: const {});
      emit(state.copyWith(busy: false));
    } catch (_) {
      emit(state.copyWith(busy: false, error: 'Could not start the game. Check your connection.'));
    }
  }

  Future<void> _onSent(SlapSent _, Emitter<SlapState> emit) async {
    final s = state.session;
    final now = DateTime.now();
    if (s == null || !s.isActive || now.difference(_lastSent) < minGap) return;
    _lastSent = now;
    emit(state.copyWith(given: state.given + 1));
    try {
      await slapRepository.slap(coupleId: _coupleId, userId: _userId);
    } catch (_) {
      emit(state.copyWith(error: 'That slap did not go through.'));
    }
  }

  Future<void> _onEnded(SlapEnded _, Emitter<SlapState> emit) async {
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
    await _sessions?.cancel();
    await _slaps?.cancel();
    return super.close();
  }
}
