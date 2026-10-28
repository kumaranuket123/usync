import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Opens a Hive box whose contents are encrypted with [cipher] (the phone's local key).
///
/// Boxes from earlier versions of the app were not encrypted and live under [legacyName]: the first time
/// the encrypted box is opened (and is empty) their entries are copied into it, then the old file is
/// deleted, so nothing readable stays behind and a queued change is not lost.
///
/// A box that cannot be opened with the key (the key was lost, for example after a restore) holds only
/// cached data and queued changes that cannot be read any more: it is discarded and started empty.
Future<Box<dynamic>> openProtectedBox(String name, HiveCipher cipher, {String? legacyName}) async {
  Box<dynamic> box;
  try {
    box = await Hive.openBox<dynamic>(name, encryptionCipher: cipher);
  } catch (e) {
    debugPrint('Local box "$name" could not be opened (${e.runtimeType}); starting it empty');
    await Hive.deleteBoxFromDisk(name);
    box = await Hive.openBox<dynamic>(name, encryptionCipher: cipher);
  }
  if (legacyName != null) await _migrateLegacy(legacyName, box);
  return box;
}

Future<void> _migrateLegacy(String legacyName, Box<dynamic> target) async {
  if (!await Hive.boxExists(legacyName)) return;
  try {
    final legacy = await Hive.openBox<dynamic>(legacyName);
    // Only into an empty box: if an earlier run copied but was interrupted before deleting, copying again
    // would repeat the entries.
    if (target.isEmpty && legacy.isNotEmpty) {
      await target.putAll(Map<dynamic, dynamic>.of(legacy.toMap()));
    }
    await legacy.close();
  } catch (e) {
    debugPrint('Could not read the old local box "$legacyName" (${e.runtimeType}); discarding it');
  }
  await Hive.deleteBoxFromDisk(legacyName);
}
