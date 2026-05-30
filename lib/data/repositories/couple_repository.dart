import 'dart:math';

import '../../domain/entities/couple.dart';
import '../../domain/repositories/i_couple_repository.dart';
import '../datasources/remote/firestore_source.dart';
import '../datasources/remote/rtdb_source.dart';
import '../models/couple_model.dart';

class CoupleRepository implements ICoupleRepository {
  CoupleRepository({required this.firestoreSource, required this.rtdbSource});

  final FirestoreSource firestoreSource;
  final RtdbSource      rtdbSource;

  @override
  Future<String> generateInviteCode(String userId) async {
    const chars  = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng    = Random.secure();
    final code   = List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
    final expiry = DateTime.now().add(const Duration(hours: 24));

    await firestoreSource.inviteCodes.doc(code).set({
      'userId':    userId,
      'expiresAt': expiry.toIso8601String(),
    });
    return code;
  }

  @override
  Future<Couple> joinWithCode(String code, String userId) async {
    final codeDoc = await firestoreSource.inviteCodes.doc(code).get();
    if (!codeDoc.exists) throw Exception('Invalid invite code');

    final data    = codeDoc.data()!;
    final expiry  = DateTime.parse(data['expiresAt'] as String);
    if (DateTime.now().isAfter(expiry)) throw Exception('Invite code expired');

    final partnerUserId = data['userId'] as String;
    if (partnerUserId == userId) throw Exception('Cannot pair with yourself');

    final coupleRef = firestoreSource.couples.doc();
    final couple    = CoupleModel(
      id:       coupleRef.id,
      userAId:  partnerUserId,
      userBId:  userId,
      pairedAt: DateTime.now(),
    );

    await coupleRef.set(couple.toJson());
    await firestoreSource.userDoc(partnerUserId).update({'coupleId': coupleRef.id});
    await firestoreSource.userDoc(userId).update({'coupleId': coupleRef.id});
    await firestoreSource.inviteCodes.doc(code).delete();

    return couple;
  }

  @override
  Future<Couple> getCouple(String coupleId) async {
    final snap = await firestoreSource.coupleDoc(coupleId).get();
    if (!snap.exists) throw Exception('Couple not found');
    return CoupleModel.fromJson(coupleId, snap.data()!);
  }

  @override
  Stream<bool> watchPartnerPresence(String coupleId, String partnerUserId) {
    return rtdbSource
        .presenceRef(coupleId, partnerUserId)
        .child('isOnline')
        .onValue
        .map((event) => (event.snapshot.value as bool?) ?? false);
  }

  @override
  Future<void> updatePresence(String coupleId, String userId, {required bool isOnline}) =>
      rtdbSource.presenceRef(coupleId, userId).update({
        'isOnline':  isOnline,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
}
