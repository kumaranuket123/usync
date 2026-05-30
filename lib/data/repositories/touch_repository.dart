import '../../domain/repositories/i_touch_repository.dart';
import '../datasources/remote/rtdb_source.dart';

class TouchRepository implements ITouchRepository {
  TouchRepository({required this.rtdbSource});
  final RtdbSource rtdbSource;

  @override
  Future<void> setTouchActive(String coupleId, String userId, {required bool isActive}) =>
      rtdbSource.touchRef(coupleId, userId).set({
        'isActive':  isActive,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

  @override
  Stream<bool> watchPartnerTouch(String coupleId, String partnerUserId) {
    return rtdbSource
        .touchRef(coupleId, partnerUserId)
        .child('isActive')
        .onValue
        .map((event) => (event.snapshot.value as bool?) ?? false);
  }

  @override
  Future<void> registerDisconnectClear(String coupleId, String userId) =>
      rtdbSource.touchRef(coupleId, userId).onDisconnect().set({'isActive': false});
}
