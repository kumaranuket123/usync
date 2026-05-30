import 'dart:typed_data';

import '../entities/memory.dart';

abstract interface class IMemoryRepository {
  Stream<List<Memory>>  watchMemories(String coupleId);
  Future<List<Memory>>  getMemories(String coupleId);
  Future<Memory>        saveMemory(Memory memory);
  Future<void>          toggleFavourite(String memoryId, String coupleId, {required bool isFavourited});
  Future<void>          deleteMemory(String memoryId, String coupleId);
  Future<String>        uploadCanvasBitmap(String coupleId, Uint8List bytes);
  Future<int>           getDoodleCount(String coupleId);
}
