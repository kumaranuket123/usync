import '../../domain/repositories/i_slap_repository.dart';
import '../datasources/remote/couple_channel_source.dart';

class SlapRepository implements ISlapRepository {
  SlapRepository({required this.channelSource});

  final CoupleChannelSource channelSource;

  @override
  Future<void> slap({required String coupleId, required String userId}) =>
      channelSource.open(coupleId).send(CoupleChannel.slap, {'user_id': userId});

  @override
  Stream<String> watchSlaps(String coupleId) => channelSource
      .open(coupleId)
      .on(CoupleChannel.slap)
      .map((m) => m['user_id'])
      .where((id) => id is String)
      .cast<String>();
}
