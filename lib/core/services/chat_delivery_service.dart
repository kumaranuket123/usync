import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/datasources/local/flutter_secure_key_store.dart';
import '../constants/supabase_config.dart';
import '../crypto/content_cipher.dart';
import '../crypto/key_service.dart';

/// Tells the sender a chat message reached this phone while the app is closed or killed.
///
/// `send-push` sends a data-only push next to the visible chat notification. If this phone is online, the
/// push starts the app in the background and [answerPush] runs. It only sends the sealed "delivered"
/// receipt for the messages waiting in the mailbox; it does not save or collect them (that happens when
/// the app is opened), so it needs no local chat database and cannot clash with a running app. A phone
/// that is offline never gets the push, so no receipt is sent and the sender keeps one tick.
class ChatDeliveryService {
  ChatDeliveryService({required this.client, required this.cipher, required this.prefs});

  final SupabaseClient     client;
  final ContentCipher      cipher;
  final SharedPreferences  prefs;

  static const _doneKey = 'chat_delivered_ids';
  static const _keep    = 200;

  /// Entry point from the push background isolate, where GetIt is not set up.
  static Future<void> answerPush({required String coupleId, required String senderId}) async {
    try {
      try {
        Supabase.instance.client;
      } catch (_) {
        await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey);
      }
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      final cipher = ContentCipher(
        keysFor: (userId) => KeyService(store: const FlutterSecureKeyStore(), namespace: userId),
        currentUserId: () => client.auth.currentUser?.id,
      );
      await ChatDeliveryService(client: client, cipher: cipher, prefs: await SharedPreferences.getInstance())
          .reportDelivered(coupleId: coupleId, senderId: senderId);
    } catch (e) {
      debugPrint('Could not report chat delivery: ${e.runtimeType}'); // best effort: one tick until the app opens
    }
  }

  /// Sends one delivered receipt for the sender's messages still waiting for this phone, leaving out the
  /// ones already reported (each push would otherwise repeat the earlier ids).
  Future<void> reportDelivered({required String coupleId, required String senderId}) async {
    final rows = await client
        .from('chat_messages')
        .select('id')
        .eq('couple_id', coupleId)
        .eq('sender_id', senderId)
        .neq('kind', 'control');
    final done = (prefs.getStringList(_doneKey) ?? const <String>[]);
    final ids = [for (final r in rows) r['id'] as String]..removeWhere(done.contains);
    if (ids.isEmpty) return;

    final id = const Uuid().v4();
    final enc = await cipher.sealJson({'c': 'receipt', 'k': 'delivered', 'ids': ids}, coupleId: coupleId, table: 'chat_messages', rowId: id);
    await client.rpc('send_chat_message', params: {
      'p_id':         id,
      'p_couple':     coupleId,
      'p_kind':       'control',
      'p_enc':        enc,
      'p_media_path': null,
      'p_ttl':        0,
    });
    final all = [...done, ...ids];
    await prefs.setStringList(_doneKey, all.sublist(all.length > _keep ? all.length - _keep : 0));
  }
}
