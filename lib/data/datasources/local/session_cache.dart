import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// The last server answers the app needs to start and work without a
/// connection: who you are, your couple, your partner, recent moods and the
/// timeline. Rows are stored as the JSON the server sent.
class SessionCache {
  SessionCache({required this.box});
  final Box<dynamic> box;

  static const boxName = 'session_cache';

  Future<void> put(String key, Object? value) => box.put(key, jsonEncode(value));

  Map<String, dynamic>? getMap(String key) {
    final raw = box.get(key);
    if (raw is! String) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  List<Map<String, dynamic>>? getList(String key) {
    final raw = box.get(key);
    if (raw is! String) return null;
    final decoded = jsonDecode(raw);
    return decoded is List
        ? [for (final e in decoded) Map<String, dynamic>.from(e as Map)]
        : null;
  }

  Future<void> clear() => box.clear();

  static String profile(String uid)       => 'profile:$uid';
  static String couple(String coupleId)   => 'couple:$coupleId';
  static String moods(String coupleId)    => 'moods:$coupleId';
  static String milestones(String coupleId) => 'milestones:$coupleId';
}
