import '../../domain/games/pen_fight.dart';
import '../../domain/repositories/i_pen_fight_repository.dart';
import '../datasources/remote/couple_channel_source.dart';

class PenFightRepository implements IPenFightRepository {
  PenFightRepository({required this.channelSource});

  final CoupleChannelSource channelSource;

  @override
  Future<void> send({required String coupleId, required PenMessage message}) =>
      channelSource.open(coupleId).send(CoupleChannel.pen, message.toJson());

  @override
  Stream<PenMessage> watch(String coupleId) => channelSource
      .open(coupleId)
      .on(CoupleChannel.pen)
      .map(PenMessage.fromJson)
      .where((m) => m != null)
      .cast<PenMessage>();

  /// The screen name the games announce on Presence (see `GameRepository.enterGame`).
  static const screen = 'game_pen_fight';

  @override
  Stream<bool> watchPartnerHere({required String coupleId, required String userId}) async* {
    final channel = channelSource.open(coupleId);
    bool here() => channel.presenceScreens.entries.any((e) => e.key != userId && e.value == screen);
    yield here();
    yield* channel.onlineUsers.stream.map((_) => here());
  }
}
