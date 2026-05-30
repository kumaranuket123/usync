import 'package:hive_flutter/hive_flutter.dart';

/// Hive boxes for offline caching.
/// Boxes are opened on first access (lazy).
class HiveSource {
  static const String _memoriesBox = 'memories_cache';

  Future<Box> get _memories async =>
      Hive.isBoxOpen(_memoriesBox)
          ? Hive.box(_memoriesBox)
          : await Hive.openBox(_memoriesBox);

  Future<void> cacheMemories(String coupleId, List<Map<String, dynamic>> data) async {
    final box = await _memories;
    await box.put(coupleId, data);
  }

  Future<List<Map<String, dynamic>>> getCachedMemories(String coupleId) async {
    final box = await _memories;
    final raw = box.get(coupleId);
    if (raw == null) return [];
    return (raw as List).cast<Map<String, dynamic>>();
  }

  Future<void> clearAll() async {
    final box = await _memories;
    await box.clear();
  }
}
