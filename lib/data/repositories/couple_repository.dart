import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/couple.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_couple_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/remote/couple_channel_source.dart';
import '../models/couple_model.dart';

class CoupleRepository implements ICoupleRepository {
  CoupleRepository({required this.client, required this.channelSource, required this.notifications});

  final SupabaseClient          client;
  final CoupleChannelSource     channelSource;
  final INotificationRepository notifications;

  @override
  Future<String> generateInviteCode(String userId) async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng   = Random.secure();
    final expiry = DateTime.now().toUtc().add(const Duration(hours: 24));

    // 4-char codes can collide; the primary key rejects a duplicate, so retry.
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
      try {
        await client.from('invite_codes').insert({
          'code':       code,
          'user_id':    userId,
          'expires_at': expiry.toIso8601String(),
        });
        return code;
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
      }
    }
    throw Exception('Could not generate an invite code, try again');
  }

  @override
  Future<Couple> joinWithCode(String code, String userId) async {
    // One transaction server-side: validates the code, creates the couple, links both profiles.
    final row = await client.rpc('join_with_code', params: {'p_code': code});
    return CoupleModel.fromRow(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<Couple> getCouple(String coupleId) async {
    final row = await client.from('couples').select().eq('id', coupleId).maybeSingle();
    if (row == null) throw Exception('Couple not found');
    return CoupleModel.fromRow(row);
  }

  @override
  Stream<Couple> watchCouple(String coupleId) => client
      .from('couples')
      .stream(primaryKey: ['id'])
      .eq('id', coupleId)
      .where((rows) => rows.isNotEmpty)
      .map((rows) => CoupleModel.fromRow(rows.first));

  @override
  Future<void> requestDisconnect(String coupleId, String userId) async {
    await client.rpc('request_disconnect', params: {'p_couple': coupleId});
    await notifications.notifyPartner(
      coupleId:   coupleId,
      fromUserId: userId,
      type:       NotifType.milestone,
      body:       (name) => '$name asked to disconnect. Open Profile to respond.',
    );
  }

  @override
  Future<void> cancelDisconnect(String coupleId) =>
      client.rpc('cancel_disconnect', params: {'p_couple': coupleId});

  /// Only the partner who did not request can confirm; enforced in the database.
  @override
  Future<void> confirmDisconnect(String coupleId, String userId) =>
      client.rpc('confirm_disconnect', params: {'p_couple': coupleId});

  // ── Presence (Realtime Presence on the shared couple channel) ──────────────
  @override
  Stream<bool> watchPartnerPresence(String coupleId, String partnerUserId) async* {
    final channel = channelSource.open(coupleId);
    await channel.ready;
    yield* channel.onlineUsers.stream.map((ids) => ids.contains(partnerUserId));
  }

  @override
  Future<void> updatePresence(String coupleId, String userId, {required bool isOnline}) async {
    final channel = channelSource.open(coupleId);
    if (isOnline) {
      await channel.track({
        'user_id':    userId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      await channel.untrack();
    }
  }
}
