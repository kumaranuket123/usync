import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/crypto/content_cipher.dart';
import '../../domain/entities/game_answer.dart';
import '../../domain/entities/game_session.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_game_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/remote/couple_channel_source.dart';
import '../models/game_session_model.dart';

class GameRepository implements IGameRepository {
  GameRepository({required this.client, required this.notifications, required this.cipher, required this.channelSource});

  final SupabaseClient          client;
  final INotificationRepository notifications;
  final ContentCipher           cipher;
  final CoupleChannelSource     channelSource;
  final _uuid = const Uuid();

  @override
  Stream<List<GameSession>> watchSessions(String coupleId) => client
      .from('game_sessions')
      .stream(primaryKey: ['id'])
      .eq('couple_id', coupleId)
      .order('updated_at', ascending: false)
      .map((rows) => rows.map(GameSessionModel.fromRow).whereType<GameSession>().toList())
      .handleError((Object _) {}); // dropped Realtime connection: keep the screen alive

  @override
  Future<String> start({
    required String coupleId,
    required String userId,
    required GameType type,
    required Map<String, dynamic> state,
  }) async {
    final newId = _uuid.v4();
    final id = await client.rpc('start_game', params: {
      'p_id':     newId,
      'p_couple': coupleId,
      'p_type':   type.key,
      'p_state':  state,
    }) as String;
    if (id != newId) return id; // joined a game the partner had just started: they know already
    await notifications.notifyPartner(
      coupleId:   coupleId,
      fromUserId: userId,
      type:       NotifType.game,
      body:       (name) => '$name started a game with you ${type.emoji}',
      detail:     (name) => '$name wants to play ${type.title}',
    );
    return id;
  }

  @override
  Future<void> makeMove({
    required GameSession session,
    required String userId,
    required Map<String, dynamic> state,
    bool finish = false,
  }) async {
    await client.rpc('make_move', params: {
      'p_session': session.id,
      'p_state':   state,
      'p_version': session.version,
      'p_finish':  finish,
    });
    if (finish) {
      await notifications.notifyPartner(
        coupleId:   session.coupleId,
        fromUserId: userId,
        type:       NotifType.game,
        body:       (name) => '$name finished your game ${session.type.emoji}',
      );
      return;
    }
    // Not awaited: working out whether the partner is here can wait for the channel to join, and
    // the move itself is already saved.
    unawaited(_notifyTurn(session, userId));
  }

  /// "It's your turn" for a partner who is not looking at the game. A push for every move would
  /// cost a notification row and a function call each time, mostly for a partner watching the board.
  Future<void> _notifyTurn(GameSession session, String userId) async {
    try {
      final channel = channelSource.open(session.coupleId);
      await channel.whenReady(const Duration(seconds: 3));
      // Before the first Presence sync we cannot tell where they are: one push too many is better
      // than a game that stalls because nobody knew it was their turn.
      if (channel.presenceSynced) {
        final screen = _screen(session.type);
        final partnerHere = channel.presenceScreens.entries.any((e) => e.key != userId && e.value == screen);
        if (partnerHere) return;
      }
      await notifications.notifyPartner(
        coupleId:   session.coupleId,
        fromUserId: userId,
        type:       NotifType.game,
        body:       (name) => "It's your turn ${session.type.emoji}",
      );
    } catch (e) {
      debugPrint('Could not send the turn notification: ${e.runtimeType}');
    }
  }

  /// What a user announces on Presence while looking at a game.
  static String _screen(GameType type) => 'game_${type.key}';

  @override
  Future<void> enterGame({required String coupleId, required String userId, required GameType type}) =>
      channelSource.open(coupleId).track({
        'user_id':    userId,
        'screen':     _screen(type),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

  @override
  Future<void> leaveGame({required String coupleId, required String userId}) =>
      channelSource.open(coupleId).track({
        'user_id':    userId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

  @override
  Future<void> updateState({required GameSession session, required Map<String, dynamic> state}) =>
      client.rpc('update_game_state', params: {'p_session': session.id, 'p_state': state, 'p_version': session.version});

  @override
  Future<void> finish(String sessionId) => client.rpc('finish_game', params: {'p_session': sessionId});

  /// Binds a sealed answer to its game, author and round, so the server cannot swap answers around.
  static String _answerRowId(String sessionId, String userId, int round) => '$sessionId:$userId:$round';

  @override
  Future<void> submitAnswer({
    required GameSession session,
    required String userId,
    required int round,
    required Map<String, dynamic> content,
    bool notify = false,
  }) async {
    final sealed = await cipher.sealJson(
      content, coupleId: session.coupleId, table: 'game_answers', rowId: _answerRowId(session.id, userId, round),
    );
    await client.rpc('submit_game_answer', params: {'p_session': session.id, 'p_round': round, 'p_enc': sealed});
    if (!notify) return;
    await notifications.notifyPartner(
      coupleId:   session.coupleId,
      fromUserId: userId,
      type:       NotifType.game,
      body:       (name) => '$name answered all of your game ${session.type.emoji}',
    );
  }

  @override
  Future<List<GameAnswer>> getAnswers(GameSession session) async {
    final rows = await client.rpc('get_game_answers', params: {'p_session': session.id}) as List;
    final answers = <GameAnswer>[];
    for (final r in rows.cast<Map<String, dynamic>>()) {
      final round = r['round_idx'] as int;
      final user  = r['user_id']   as String;
      Map<String, dynamic>? content;
      try {
        content = await cipher.openJson(
          r['enc'] as String, coupleId: session.coupleId, table: 'game_answers', rowId: _answerRowId(session.id, user, round),
        );
      } catch (e) {
        debugPrint('Could not read a game answer: ${e.runtimeType}'); // shown as unreadable, not dropped
      }
      answers.add(GameAnswer(round: round, userId: user, content: content));
    }
    return answers;
  }
}
