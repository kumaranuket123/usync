import '../games/pen_fight.dart';

abstract interface class IPenFightRepository {
  /// Sends [message] to the partner; they get it at once if they are in the game. Nothing is stored.
  Future<void> send({required String coupleId, required PenMessage message});

  /// What the partner sends. Messages that are not Pen Fight's, or are malformed, are skipped.
  Stream<PenMessage> watch(String coupleId);

  /// Whether the partner has the Pen Fight screen open (from Presence, which lasts and survives
  /// reconnects, unlike a one-off message). Emits the current answer first, then every change.
  Stream<bool> watchPartnerHere({required String coupleId, required String userId});
}
