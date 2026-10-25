import 'dart:async';

import '../../domain/repositories/i_touch_repository.dart';
import '../datasources/remote/couple_channel_source.dart';

/// Touch state is a Broadcast event on the couple channel. There is no
/// `onDisconnect`; instead the partner counts as not touching once their
/// Presence leaves the channel.
class TouchRepository implements ITouchRepository {
  TouchRepository({required this.channelSource});
  final CoupleChannelSource channelSource;

  @override
  Future<void> setTouchActive(String coupleId, String userId, {required bool isActive}) =>
      channelSource.open(coupleId).send(CoupleChannel.touch, {
        'user_id':   userId,
        'is_active': isActive,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

  @override
  Stream<bool> watchPartnerTouch(String coupleId, String partnerUserId) {
    final channel = channelSource.open(coupleId);
    final out     = StreamController<bool>();
    StreamSubscription<Map<String, dynamic>>? touchSub;
    StreamSubscription<Set<String>>?          presenceSub;

    // Press and long-press both send "active", and presence re-syncs often;
    // only forward real changes.
    var last = false;
    void emit(bool active) {
      if (active == last || out.isClosed) return;
      last = active;
      out.add(active);
    }

    out.onListen = () {
      touchSub = channel.on(CoupleChannel.touch).listen((msg) {
        if (msg['user_id'] == partnerUserId) emit(msg['is_active'] == true);
      });
      presenceSub = channel.onlineUsers.stream.listen((ids) {
        if (!ids.contains(partnerUserId)) emit(false);
      });
    };
    out.onCancel = () {
      touchSub?.cancel();
      presenceSub?.cancel();
    };
    return out.stream;
  }

  @override
  Future<void> registerDisconnectClear(String coupleId, String userId) =>
      // Announce ourselves on Presence so the partner can detect us leaving.
      channelSource.open(coupleId).track({
        'user_id':    userId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
}
