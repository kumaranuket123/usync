import '../../domain/repositories/i_auth_repository.dart';
import '../../domain/repositories/i_couple_repository.dart';

/// Who is signed in, and who their partner is (null when unpaired or disconnected).
typedef EncryptionContext = ({String userId, String? coupleId, String? partnerId});

abstract interface class EncryptionContextSource {
  Future<EncryptionContext?> current();
}

/// The real source: the signed-in user and their couple from the app's repositories.
class AppEncryptionContext implements EncryptionContextSource {
  AppEncryptionContext({required this.authRepository, required this.coupleRepository});

  final IAuthRepository   authRepository;
  final ICoupleRepository coupleRepository;

  @override
  Future<EncryptionContext?> current() async {
    final user = await authRepository.getCurrentUser();
    if (user == null) return null;
    final coupleId = user.coupleId;
    if (coupleId == null) return (userId: user.id, coupleId: null, partnerId: null);
    final couple = await coupleRepository.getCouple(coupleId);
    if (couple.isDisconnected) return (userId: user.id, coupleId: null, partnerId: null);
    return (userId: user.id, coupleId: coupleId, partnerId: couple.partnerIdFor(user.id));
  }
}
