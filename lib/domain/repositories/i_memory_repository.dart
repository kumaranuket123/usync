import 'dart:typed_data';

import '../entities/memory.dart';

abstract interface class IMemoryRepository {
  Stream<List<Memory>>  watchMemories(String coupleId);
  Future<List<Memory>>  getMemories(String coupleId);
  Future<Memory>        saveMemory(Memory memory);
  /// Uploads the drawing and saves it as a canvas memory, notifying the partner.
  /// Returns true when it reached the server, false when it was saved on the
  /// device to be sent once there is a connection.
  Future<bool>          saveDoodle({
    required String    coupleId,
    required String    userId,
    required Uint8List png,
    required String    title,
  });
  Future<void>          toggleFavourite(String memoryId, String coupleId, {required bool isFavourited});
  Future<void>          deleteMemory(String memoryId, String coupleId);
  Future<String>        uploadCanvasBitmap(String coupleId, Uint8List bytes);
}
