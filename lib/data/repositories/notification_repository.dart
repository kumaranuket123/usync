import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../datasources/remote/firestore_source.dart';
import '../models/notification_model.dart';

class NotificationRepository implements INotificationRepository {
  NotificationRepository({required this.firestoreSource});
  final FirestoreSource firestoreSource;

  @override
  Future<List<NotificationItem>> getNotifications(String coupleId) async {
    final snap = await firestoreSource
        .notifItems(coupleId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();
    return snap.docs.map((d) => NotificationModel.fromJson(d.id, d.data())).toList();
  }

  @override
  Stream<List<NotificationItem>> watchNotifications(String coupleId) {
    return firestoreSource
        .notifItems(coupleId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => NotificationModel.fromJson(d.id, d.data())).toList());
  }

  @override
  Future<void> markRead(String coupleId, String notificationId) =>
      firestoreSource.notifDoc(coupleId, notificationId).update({'isRead': true});

  @override
  Future<void> markAllRead(String coupleId) async {
    final snap = await firestoreSource
        .notifItems(coupleId)
        .where('isRead', isEqualTo: false)
        .get();
    final batch = firestoreSource.firestore.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  @override
  Stream<int> watchUnreadCount(String coupleId) {
    return firestoreSource
        .notifItems(coupleId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.size);
  }

  @override
  Future<void> toggleFcm({required bool enabled, required String uid}) async {
    if (enabled) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await firestoreSource.userDoc(uid).update({'fcmToken': token});
      }
    } else {
      await FirebaseMessaging.instance.deleteToken();
      await firestoreSource.userDoc(uid).update({'fcmToken': null});
    }
  }
}
