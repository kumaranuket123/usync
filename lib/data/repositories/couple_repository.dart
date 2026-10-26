import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/network_errors.dart';
import '../../domain/entities/couple.dart';
import '../../domain/repositories/i_couple_repository.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/local/identity_cache.dart';
import '../datasources/local/session_cache.dart';
import '../datasources/remote/couple_channel_source.dart';
import '../datasources/remote/storage_source.dart';
import '../models/couple_model.dart';

class CoupleRepository implements ICoupleRepository {
  CoupleRepository({
    required this.client,
    required this.channelSource,
    required this.notifications,
    required this.storage,
    required this.sessionCache,
    required this.identity,
  });

  final SupabaseClient          client;
  final CoupleChannelSource     channelSource;
  final INotificationRepository notifications;
  final StorageSource           storage;
  final SessionCache            sessionCache;
  final IdentityCache           identity;

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
    identity.clear(); // both profiles now point at the new couple
    return CoupleModel.fromRow(Map<String, dynamic>.from(row as Map));
  }

  @override
  Stream<void> watchPartnerJoined(String userId) {
    late final StreamController<void> out;
    StreamSubscription<void>? live;
    Timer? poll;

    void joined() {
      if (out.isClosed) return;
      identity.clear(); // the profile now points at the new couple
      out.add(null);
      out.close();
    }

    out = StreamController<void>(
      onListen: () {
        // The inviter is `user_a` of the couple the join creates. A disconnected
        // couple from before does not count.
        live = client
            .from('couples')
            .stream(primaryKey: ['id'])
            .eq('user_a_id', userId)
            .listen((rows) {
          if (rows.any((r) => r['disconnected_at'] == null)) joined();
        }, onError: (Object _) {});
        // Realtime can drop or lag; checking the profile now and then is the safety net.
        poll = Timer.periodic(const Duration(seconds: 4), (_) async {
          try {
            final row = await client.from('profiles').select('couple_id').eq('id', userId).maybeSingle();
            if (row?['couple_id'] != null) joined();
          } catch (_) {}
        });
      },
      onCancel: () {
        live?.cancel();
        poll?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<Couple> getCouple(String coupleId) =>
      identity.couples.get(coupleId, () => _loadCouple(coupleId));

  Future<Couple> _loadCouple(String coupleId) async {
    try {
      final row = await client.from('couples').select().eq('id', coupleId).maybeSingle();
      if (row == null) throw Exception('Couple not found');
      await sessionCache.put(SessionCache.couple(coupleId), row);
      return CoupleModel.fromRow(row);
    } catch (e) {
      // Offline: the last copy keeps the app usable.
      final cached = isNetworkError(e) ? sessionCache.getMap(SessionCache.couple(coupleId)) : null;
      if (cached != null) return CoupleModel.fromRow(cached);
      rethrow;
    }
  }

  @override
  Stream<Couple> watchCouple(String coupleId) => client
      .from('couples')
      .stream(primaryKey: ['id'])
      .eq('id', coupleId)
      .where((rows) => rows.isNotEmpty)
      .map((rows) {
        final couple = CoupleModel.fromRow(rows.first);
        identity.couples.put(coupleId, couple); // keep the remembered copy current
        return couple;
      })
      .handleError((Object _) {}); // dropped Realtime connection: keep the screen alive

  @override
  Future<void> disconnect(String coupleId, String userId) async {
    // Memory images live in Storage, which SQL cannot clear, and the storage policy
    // only lets an active member delete them: so they go first. The rows go with the RPC.
    await storage.removeFolder(coupleId);
    await client.rpc('disconnect_couple', params: {'p_couple': coupleId});
    // Nothing of the couple may stay behind on this phone either.
    await sessionCache.clear();
    identity.clear(); // the couple ends and both profiles lose their couple_id
  }

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
